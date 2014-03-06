" FilePathConvert.vim: Convert filespec between absolute, relative, and URL formats.
"
" DEPENDENCIES:
"   - ingo/compat.vim autoload script
"   - ingo/fs/path.vim autoload script
"   - ingo/os.vim autoload script
"   - ingo/selection/frompattern.vim autoload script
"
" Copyright: (C) 2012-2014 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS
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
    call ingo#selection#frompattern#Select('v', '\f\+', line('.'))
    return 1
endfunction

function! s:GetType( filespec )
    if a:filespec =~# '^[/\\][^/\\]' || (ingo#os#IsWinOrDos() && a:filespec =~? '^\a:[/\\]')
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

    if expand('%:h') !=# '.'
	" Need to change into the file's directory first to get glob results
	" relative to the file.
	let l:save_cwd = getcwd()
	let l:chdirCommand = (haslocaldir() ? 'lchdir!' : 'chdir!')
	execute l:chdirCommand '%:p:h'
    endif
    try
	let l:relativeFilespec = ingo#fs#path#Normalize(a:filespec)
	let l:absoluteFilespec = fnamemodify(l:relativeFilespec, ':p')
"****D echomsg '****' string(a:baseDir) string(l:absoluteFilespec)
	if strpart(l:absoluteFilespec, 0, len(a:baseDir)) ==# a:baseDir
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
    let l:drive = matchstr(a:filespec, '^\a:')
    return (empty(l:drive) ? ingo#fs#path#Combine(a:baseDir, a:filespec) : a:filespec)
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
	if l:currentHead ==# l:absoluteHead
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

function! FilePathConvert#FilePathConvert( text )
    let l:rootDir = ingo#fs#path#GetRootDir(expand('%:p:h'))
    let l:type = s:GetType(a:text)

    if l:type ==# 'rel'
	return FilePathConvert#RelativeToAbsolute(l:rootDir, a:text)
    elseif l:type ==# 'abs'
	return FilePathConvert#AbsoluteToRelative(l:rootDir, a:text)
    elseif l:type ==# 'url'
	throw 'TODO: not yet implemented'
    else
	throw 'ASSERT: Unknown type ' . string(l:type)
    endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
