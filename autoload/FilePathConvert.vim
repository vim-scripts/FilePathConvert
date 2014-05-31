" FilePathConvert.vim: Convert filespec between absolute, relative, and URL formats.
"
" DEPENDENCIES:
"   - ingo/avoidprompt.vim autoload script
"   - ingo/codec/URL.vim autoload script
"   - ingo/compat.vim autoload script
"   - ingo/fs/path.vim autoload script
"   - ingo/fs/path/split.vim autoload script
"   - ingo/os.vim autoload script
"   - ingo/query.vim autoload script
"   - ingo/query/confirm.vim autoload script
"   - ingo/selection/frompattern.vim autoload script
"   - ingo/str.vim autoload script
"
" Copyright: (C) 2012-2014 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS
"   2.00.014	22-May-2014	Factor out ingo#fs#path#split#AtBasePath() for
"				reuse.
"				Canonicalize absolute filespecs to handle "/./"
"				or "ignoredDir/../" path fragments.
"   2.00.013	21-May-2014	Handle case-insensitive file systems by choosing
"				the correct comparison.
"				Allow extension via b:basedir / b:baseurl pair.
"   2.00.012	20-May-2014	Also handle complete mapped filespecs (i.e.
"				without l:urlRest).
"				Use ingo#query#Confirm() to support automated
"				testing.
"				Use URL codec from ingo-library.
"   1.10.011	07-May-2014	Don't attempt to :chdir when the current buffer
"				has no name, and therefore its directory is also
"				empty. This doesn't actually do harm, but is not
"				necessary.
"				Detect failure of fnamemodify() to convert an
"				inexistent relative path to an absolute one, and
"				attempt to convert the upwards ../../ path
"				separately.
"				Add g:FilePathConvert_AdditionalIsFnamePattern
"				to correctly grab URLs on Unix and Windows-style
"				filespecs on Cygwin.
"				On Cygwin, also consider C:\-style filespecs as
"				absolute paths.
"   1.10.010	29-Apr-2014	Implement conversion to / from UNC and URL paths
"				via g:FilePathConvert_UrlMappings configuration
"				and a user query in case there's no unique
"				mapping.
"   1.10.009	28-Apr-2014	Duplicate FilePathConvert#FilePathConvert() into
"				FilePathConvert#ToLocal() and
"				FilePathConvert#ToGlobal() to support file://
"				URLs.
"   1.00.008	13-Sep-2013	Use operating system detection functions from
"				ingo/os.vim.
"	007	08-Aug-2013	Move escapings.vim into ingo-library.
"	006	23-Jul-2013	Move ingointegration#SelectCurrentRegexp() into
"				ingo-library.
"	005	01-Jun-2013	Move ingofile.vim into ingo-library.
"	004	28-Aug-2012	Rename algorithm function for better display by
"				SubstitutionsHelp.vim.
"   	003	12-Jun-2012	FIX: Do not clobber the global CWD when the
"				buffer has a local CWD set.
"	002	18-May-2012	Pass baseDir and pathSeparator into the
"				functions.
"				Improve variable names.
"				Handle implicit current drive letter in absolute
"				paths.
"	001	18-May-2012	file creation
let s:save_cpo = &cpo
set cpo&vim

function! FilePathConvert#FileSelection()
    call ingo#selection#frompattern#Select('v',
    \   '\%(\f' . (empty(g:FilePathConvert_AdditionalIsFnamePattern) ? '' : '\|' . g:FilePathConvert_AdditionalIsFnamePattern) . '\)\+',
    \   line('.')
    \)
    return 1
endfunction
let s:uncPathExpr = '^[/\\]\{2}[^/\\]'
function! s:GetType( filespec )
    if a:filespec =~# s:uncPathExpr  " UNC notation
	return 'unc'
    elseif a:filespec =~# '^[/\\]' || ((ingo#os#IsWinOrDos() || ingo#os#IsCygwin()) && a:filespec =~? '^\a:[/\\]')
	return 'abs'
    elseif a:filespec =~? '^[a-z+.-]\+:' " RFC 1738
	return 'url'
    else
	return 'rel'
    endif
endfunction


function! FilePathConvert#RelativeToAbsolute( baseDir, filespec )
    if s:GetType(a:filespec) !=# 'rel'
	throw 'Not a relative file: ' . a:filespec
    endif

    if ! empty(expand('%')) && expand('%:h') !=# '.'
	" Need to change into the file's directory first to get glob results
	" relative to the file.
	let l:save_cwd = getcwd()
	let l:chdirCommand = (haslocaldir() ? 'lchdir!' : 'chdir!')
	execute l:chdirCommand '%:p:h'
    endif
    try
	let l:relativeFilespec = ingo#fs#path#Normalize(a:filespec)
	let l:absoluteFilespec = fnamemodify(l:relativeFilespec, ':p')
	if ingo#str#Equals(l:absoluteFilespec, l:relativeFilespec, ingo#fs#path#IsCaseInsensitive(l:absoluteFilespec))
	    " From :h filename-modifiers: For a file name that does not exist
	    " and does not have an absolute path the result is unpredictable.
	    " On Windows, this seems to work, but it doesn't on Cygwin.
	    " If the upwards ../../ path part does exist, we can convert that
	    " part alone and concatenate again with the remainder as a
	    " workaround.
	    let [l:upwardPath, l:remainder] = matchlist(l:relativeFilespec, '^\(\%(\.\.[/\\]\)*\)\(.*\)$')[1:2]
	    if ! empty(l:upwardPath)
		let l:absoluteFilespec = fnamemodify(l:upwardPath, ':p') . l:remainder
	    endif
	endif
"****D echomsg '****' string(a:baseDir) string(l:absoluteFilespec)
	if ingo#str#Equals(strpart(l:absoluteFilespec, 0, len(a:baseDir)), a:baseDir, ingo#fs#path#IsCaseInsensitive(a:baseDir))
	    if ingo#fs#path#IsCaseInsensitive(a:baseDir) && fnamemodify(l:absoluteFilespec, ':t') !=# fnamemodify(l:relativeFilespec, ':t')
		" When the relative filename's case differs from the actual one,
		" fnamemodify() returns (on Windows) the actual case, but
		" doesn't do that for path components with differing case. For
		" consistency, use the case from the original, relative
		" filespec.
		return ingo#fs#path#Combine(fnamemodify(l:absoluteFilespec, ':h'), fnamemodify(l:relativeFilespec, ':t'))
	    endif
	    return l:absoluteFilespec
	else
	    throw 'Link to outside of root dir: ' . l:absoluteFilespec
	endif
    finally
	if exists('l:save_cwd')
	    execute l:chdirCommand ingo#compat#fnameescape(l:save_cwd)
	endif
    endtry
endfunction


function! s:NormalizeBaseDir( baseDir, filespec )
    return ((! ingo#os#IsWinOrDos() || a:filespec =~# '^\a:\|' . s:uncPathExpr) ?
    \   a:filespec :
    \   ingo#fs#path#Combine(a:baseDir, a:filespec)
    \)
endfunction
function! s:NormalizeBase( filespec )
    return substitute(a:filespec, '^\a:', '', '')
endfunction
function! s:IsOnDifferentRoots( filespecA, filespecB, pathSeparator )
    if ! ingo#os#IsWinOrDos()
	return 0
    endif

    if matchstr(a:filespecA, '^\a:') !=? matchstr(a:filespecB, '^\a:')
	return 1
    endif

    let l:ps = escape(a:pathSeparator, '\')
    if
    \   matchstr(a:filespecA, printf('^%s%s[^%s]\+%s[^%s]\+', l:ps, l:ps, l:ps, l:ps, l:ps)) !=?
    \   matchstr(a:filespecB, printf('^%s%s[^%s]\+%s[^%s]\+', l:ps, l:ps, l:ps, l:ps, l:ps))
	return 1
    endif

    return 0
endfunction
function! s:HeadAndRest( filespec, pathSeparator )
    let l:ps = escape(a:pathSeparator, '\')
    return [
    \   matchstr(a:filespec, printf('%s[^%s]*', l:ps, l:ps)),
    \   matchstr(a:filespec, printf('%s[^%s]*\zs.*$', l:ps, l:ps))
    \]
endfunction
function! FilePathConvert#AbsoluteToRelative( baseDir, filespec )
    let l:pathSeparator = ingo#fs#path#Separator()
    let l:currentDirspec = expand('%:p:h') . l:pathSeparator
    if strpart(l:currentDirspec, 0, len(a:baseDir)) !=# a:baseDir
	throw 'File outside of root dir: ' . a:baseDir
    endif

    " To generate the relative filespec, we need the dirspec part of the current
    " buffer, and the absolute source filespec.
    let l:absoluteFilespec = ingo#fs#path#Normalize(s:NormalizeBaseDir(ingo#fs#path#GetRootDir(getcwd()), a:filespec), l:pathSeparator)
"****D echomsg '****' string(a:baseDir) string(l:absoluteFilespec) string(l:currentDirspec)
    if s:IsOnDifferentRoots(l:currentDirspec, l:absoluteFilespec, l:pathSeparator)
	throw 'File has a different root'
    endif
    " Determine the directory where both diverge by stripping the head directory
    " off both if they are identical.
    let l:current  = s:NormalizeBase(l:currentDirspec)
    let l:absolute = s:NormalizeBase(l:absoluteFilespec)
    while 1
"****D echomsg '####' string(l:current) string(l:absolute)
	let [l:currentHead , l:currentRest ] = s:HeadAndRest(l:current , l:pathSeparator)
	let [l:absoluteHead, l:absoluteRest] = s:HeadAndRest(l:absolute, l:pathSeparator)
"****D echomsg '####' string(l:currentHead) string(l:absoluteHead)
	if ingo#str#Equals(l:currentHead, l:absoluteHead, ingo#fs#path#IsCaseInsensitive(l:absoluteHead))
	    let l:current  = l:currentRest
	    let l:absolute = l:absoluteRest
	else
	    break
	endif
    endwhile
"****D echomsg '****' string(l:current) string(l:absolute)
    " The remaining dirspec part of the current buffer must be traversed up to go
    " to the directory where both diverge. From there, traverse down what
    " remains of the stripped source filespec.
    let l:dirUp = substitute(l:current[1:], printf('[^%s]\+', escape(l:pathSeparator, '\')), '..', 'g')
    let l:relativeFilespec = l:dirUp . l:absolute[1:]
"****D echomsg '****' string(l:dirUp) string(l:relativeFilespec)
    return l:relativeFilespec
endfunction


function! FilePathConvert#AbsoluteToUncOrUrl( baseDir, filespec )
    " Search URL mapping values, use matching key.
    let l:urlMappings = s:GetUrlMappings()
    let l:filespec = ingo#fs#path#Combine(ingo#fs#path#Normalize(a:filespec, '/'), '')

    let l:urls = []
    for l:baseUrl in keys(l:urlMappings)
	for l:mappedFilespec in ingo#list#Make(l:urlMappings[l:baseUrl])
	    let l:filespecSuffix = ingo#fs#path#split#AtBasePath(a:filespec, l:mappedFilespec)
	    if type(l:filespecSuffix) == type('')
		if l:baseUrl =~# s:uncPathExpr
		    let l:url = ingo#fs#path#Normalize(empty(l:filespecSuffix) ?
		    \   l:baseUrl :
		    \   ingo#fs#path#Combine(l:baseUrl, l:filespecSuffix)
		    \)
		else
		    let l:url = (empty(l:filespecSuffix) ?
		    \   l:baseUrl :
		    \   ingo#fs#path#Combine(l:baseUrl, ingo#codec#URL#FilespecEncode(l:filespecSuffix))
		    \)
		endif

		call add(l:urls, l:url)
	    endif
	    unlet l:filespecSuffix
	endfor
    endfor

    if empty(l:urls)
	throw 'No URL mapping defined for filespec ' . a:filespec
    endif

    return s:Query('URL', l:urls)
endfunction
function! s:Query( what, list )
    if len(a:list) == 0
	return ''
    elseif len(a:list) == 1
	return a:list[0]
    endif

    let l:defaultChoice = 1
    let l:choice = ingo#query#Confirm(
    \   printf('Choose %s:', a:what),
    \   join(ingo#query#confirm#AutoAccelerators(copy(a:list), l:defaultChoice), "\n"),
    \   l:defaultChoice
    \)

    if l:choice == 0
	throw 'Aborted'
    else
	return a:list[l:choice - 1]
    endif
endfunction

function! FilePathConvert#UncToUrl( baseDir, filespec )
    return 'file:///' . ingo#codec#URL#FilespecEncode(a:filespec)
endfunction

function! s:GetUrlMappings()
    let l:urlMappings = ingo#plugin#setting#GetBufferLocal('FilePathConvert_UrlMappings')

    " Allow extension via b:basedir / b:baseurl pair.
    if exists('b:basedir') && exists('b:baseurl')
	let l:urlMappings[b:baseurl] = b:basedir
    endif

    return l:urlMappings
endfunction
function! s:UrlMappingToAbsolute( filespec )
    " Search URL mapping keys, use matching value.
    let l:urlMappings = s:GetUrlMappings()

    let l:absoluteFilespecs = []
    for l:baseUrl in keys(l:urlMappings)
	let l:urlRest = ingo#fs#path#split#AtBasePath(a:filespec, l:baseUrl)
	if type(l:urlRest) == type('')
	    for l:mappedFilespec in ingo#list#Make(l:urlMappings[l:baseUrl])
		let l:absoluteFilespec = (empty(l:urlRest) ?
		\   l:mappedFilespec :
		\   ingo#fs#path#Combine(
		\       l:mappedFilespec,
		\       ingo#codec#URL#Decode(l:urlRest)
		\   )
		\)
		call add(l:absoluteFilespecs, l:absoluteFilespec)
	    endfor
	endif
	unlet l:urlRest
    endfor

    return s:Query('filespec', l:absoluteFilespecs)
endfunction

function! FilePathConvert#UncToAbsolute( baseDir, filespec )
    let l:absoluteFilespec = s:UrlMappingToAbsolute(a:filespec)
    if empty(l:absoluteFilespec)
	throw 'No URL mapping defined for UNC path ' . a:filespec
    endif
    return l:absoluteFilespec
endfunction
function! FilePathConvert#UrlToAbsolute( baseDir, filespec )
    let l:absoluteFilespec = s:UrlMappingToAbsolute(a:filespec)
    if ! empty(l:absoluteFilespec)
	return l:absoluteFilespec
    endif

    " Fallback: Convert file: URLs to UNC path.
    if a:filespec =~# '^file://'
	call ingo#msg#WarningMsg(ingo#avoidprompt#Truncate('No URL mappings defined for URL ' . a:filespec . '; converting to UNC path'))
	return ingo#fs#path#Normalize('//' . ingo#codec#URL#Decode(matchstr(a:filespec, '^[a-z+.-]\+:/\+\zs.*$')))
    endif

    throw 'No URL mapping defined for URL ' . a:filespec
endfunction



function! s:FilePathConvert( isToLocal, text )
    let l:rootDir = ingo#fs#path#GetRootDir(expand('%:p:h'))
    let l:type = s:GetType(a:text)

    if l:type ==# 'rel'
	return FilePathConvert#RelativeToAbsolute(l:rootDir, a:text)
    elseif l:type ==# 'abs'
	" Though the filename has been determined as absolute, it may not yet be
	" in canonical form; i.e. contain "/./" or "ignoredDir/../" path
	" fragments, which would prevent a match with the base dir / URL
	" mappings.
	let l:absoluteFilespec = fnamemodify(a:text, ':p')

	if a:isToLocal
	    return FilePathConvert#AbsoluteToRelative(l:rootDir, l:absoluteFilespec)
	else
	    return FilePathConvert#AbsoluteToUncOrUrl(l:rootDir, l:absoluteFilespec)
	endif
    elseif l:type ==# 'unc'
	if a:isToLocal
	    return FilePathConvert#UncToAbsolute(l:rootDir, a:text)
	else
	    return FilePathConvert#UncToUrl(l:rootDir, a:text)
	endif
    elseif l:type ==# 'url'
	return FilePathConvert#UrlToAbsolute(l:rootDir, a:text)
    else
	throw 'ASSERT: Unknown type ' . string(l:type)
    endif
endfunction
function! FilePathConvert#ToLocal( text )
    return s:FilePathConvert(1, a:text)
endfunction
function! FilePathConvert#ToGlobal( text )
    return s:FilePathConvert(0, a:text)
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
