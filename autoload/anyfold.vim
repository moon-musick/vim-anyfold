" AnyFold plugin
"----------------------------------------------------------------------------/
" Activation of requested features
"----------------------------------------------------------------------------/
function anyfold#init() abort

    if exists("b:anyfold_initialised")
        return
    endif

    if !exists('g:_ANYFOLD_DEFAULTS')
        let g:_ANYFOLD_DEFAULTS = {
                    \ 'identify_comments':            0,
                    \ 'fold_comments':                0,
                    \ 'fold_toplevel':                0,
                    \ 'fold_display':                 1,
                    \ 'motion':                       1,
                    \ 'toggle_key':                   '<space>',
                    \ 'auto_reload':                  1,
                    \ 'debug':                        0,
                    \ }
        lockvar! g:_ANYFOLD_DEFAULTS
    endif

    for s:key in keys(g:_ANYFOLD_DEFAULTS)
        if !exists('g:anyfold_' . s:key)
            let g:anyfold_{s:key} = copy(g:_ANYFOLD_DEFAULTS[s:key])
        endif
    endfor
    if g:anyfold_fold_comments
        let g:anyfold_identify_comments = 1
    endif

    let b:anyfold_numlines = line('$')

    if g:anyfold_identify_comments
        let b:anyfold_commentlines = s:MarkCommentLines()
        lockvar! b:anyfold_commentlines
    endif

    let b:anyfold_indent_list = s:InitIndentList()
    lockvar! b:anyfold_indent_list

    if !&diff
        setlocal foldmethod=expr
        setlocal foldexpr=GetIndentFold(v:lnum)
    endif

    if g:anyfold_fold_display
        setlocal foldtext=MinimalFoldText()
    endif

    if g:anyfold_auto_reload
        let s:foldcmd_reload = ['zc', 'zC', 'za', 'zA', 'zx', 'zX', 'zm', 'zM', '[z', ']z', 'zj', 'zk']
        for s:cmd in s:foldcmd_reload
            exe 'noremap <buffer> <silent> '.s:cmd.' :call <SID>ReloadFolds(0)<cr>'.s:cmd
            exe 'vnoremap <buffer> <silent> '.s:cmd.' :<c-u>call <SID>ReloadFolds(0)<cr>gv'.s:cmd
        endfor
        autocmd BufWritePre * :call s:ReloadFolds(1)
    endif

    exe 'noremap <script> <buffer> <silent> '.g:anyfold_toggle_key.
                    \' :call <SID>ToggleFolds()<cr>'

    if g:anyfold_motion
        noremap <script> <buffer> <silent> ]]
                    \ :call <SID>JumpFoldEnd(0)<cr>

        noremap <script> <buffer> <silent> [[
                    \ :call <SID>JumpFoldStart(0)<cr>

        noremap <script> <buffer> <silent> ]k
                    \ :call <SID>JumpPrevFoldEnd(0)<cr>

        noremap <script> <buffer> <silent> [j
                    \ :call <SID>JumpNextFoldStart(0)<cr>

        vnoremap <script> <buffer> <silent> ]]
                    \ :<c-u>call <SID>JumpFoldEnd(1)<cr>

        vnoremap <script> <buffer> <silent> [[
                    \ :<c-u>call <SID>JumpFoldStart(1)<cr>

        vnoremap <script> <buffer> <silent> ]k
                    \ :<c-u>call <SID>JumpPrevFoldEnd(1)<cr>

        vnoremap <script> <buffer> <silent> [j
                    \ :<c-u>call <SID>JumpNextFoldStart(1)<cr>
    endif

    if g:anyfold_debug
        noremap <script> <buffer> <silent> <F9>
                    \ :echom <SID>IsComment(line('.'))<cr>
        noremap <script> <buffer> <silent> <F10>
                    \ :call <SID>echoLineIndent()<cr>
        noremap <script> <buffer> <silent> <F11>
                    \ :call <SID>echoIndentList()<cr>
    endif

    let b:anyfold_initialised = 1
    doautocmd User AnyFoldLoaded
endfunction

function! s:CommentLine(lnum, force) abort
    " unindented comments and preprocessor statements
    " Note: synID is very slow, therefore we identify unindented comments only
    " (or if force==1)
    if indent(a:lnum) >= &sw && !a:force
        return 0
    else
        return synIDattr(synID(a:lnum,indent(a:lnum)+1,1),"name") =~? 'Comment'
               \ || getline(a:lnum)[0] == '#'
    endif
endfunction

function! s:IsComment(lnum) abort
    if g:anyfold_identify_comments
        if a:lnum <= line('$') && a:lnum > 0
            return b:anyfold_commentlines[a:lnum-1]
        else
            return 0
        endif
    else
        return 0
    endif
endfunction

"----------------------------------------------------------------------------/
" Folding
"----------------------------------------------------------------------------/
function! s:NextNonBlankLine(lnum) abort
    let numlines = line('$')
    let current = a:lnum + 1

    while current <= numlines
        if getline(current) =~? '\v\S' && !s:IsComment(current)
            return current
        endif

        let current += 1
    endwhile

    return -1
endfunction

function! s:PrevNonBlankLine(lnum) abort
    let current = a:lnum - 1

    while current > 0
        if getline(current) =~? '\v\S' && !s:IsComment(current)
            return current
        endif

        let current += -1
    endwhile

    return 0
endfunction

" get indent hierarchy from actual indents
function! s:InitIndentList() abort

    " get list of actual indents (ind_list)
    let numlines = line('$')
    let ind_list = [0]
    let current = 1
    while current <= numlines
        let prev_indent = indent(s:PrevNonBlankLine(current))
        let next_indent = indent(s:NextNonBlankLine(current))
        if getline(current) =~? '\v\S' && !s:IsComment(current)
            let ind_list += [indent(current)]
        else
            let ind_list += [max([prev_indent,next_indent])]
        endif
        let current += 1
    endwhile
    let ind_list = ind_list[1:]
    " get hierarchical list of indents (hierind_list)
    let prev_ind = ind_list[-1]
    let hierind_list = [0]
    let ind_open_list = [0]
    for ind in ind_list
        if ind > prev_ind
            let hierind_list += [hierind_list[-1] + 1]
            let ind_open_list += [ind]
        elseif ind == prev_ind
            let hierind_list += [hierind_list[-1]]
            if ind_open_list[-1] < ind
                let ind_open_list += [ind]
            elseif ind_open_list[-1] > ind
                let ind_open_list[-1] = ind
            endif
        elseif ind < prev_ind
            let n_closed = 0
            while ind < ind_open_list[-1] && ind <= ind_open_list[-2]
                let ind_open_list = ind_open_list[:-2]
                let n_closed += 1
            endwhile
            let hierind_list += [hierind_list[-1]-n_closed]
        endif
        let prev_ind = ind
    endfor
    let hierind_list = hierind_list[1:]

    return hierind_list
endfunction

function! s:MarkCommentLines() abort
    let numlines = line('$')
    let commentlines = []
    let current = 1
    while current <= numlines
        " here we force identification of a comment line if it may belong to a
        " multiline comment (in this case we can not assume that it is
        " unindented)
        if current > 1
            let force = commentlines[-1]
        else
            let force = 0
        endif
        let commentlines += [0]
        if s:CommentLine(current, force)
            let commentlines[-1] = 1
        endif
        let current += 1
    endwhile
    return commentlines
endfunction

function! GetIndentFold(lnum) abort

    if s:IsComment(a:lnum) && (s:IsComment(a:lnum-1) || s:IsComment(a:lnum+1))
        if g:anyfold_fold_comments
            " introduce artifical fold for docuboxes
            return max([b:anyfold_indent_list[a:lnum-1] + 1, 2])
        endif
    endif

    let this_indent = b:anyfold_indent_list[a:lnum-1]

    if a:lnum == len(b:anyfold_indent_list)-1
        return this_indent
    endif

    let next_indent = b:anyfold_indent_list[a:lnum]

    " heuristics to define blocks at foldlevel 0
    if g:anyfold_fold_toplevel && this_indent == 0

        let prev_indent = b:anyfold_indent_list[a:lnum-2]

        if a:lnum == 1
            let prevprev_indent = 0
        else
            let prevprev_indent = b:anyfold_indent_list[a:lnum-3]
        endif

        if a:lnum >= line('$') - 1
            let nextnext_indent = 0
        else
            let nextnext_indent = b:anyfold_indent_list[a:lnum+1]
        endif

        if next_indent > 0
            return '>1'
        endif

        if prev_indent > 0
            return 0
        else
            if prevprev_indent > 0
                if next_indent == 0 && nextnext_indent == 0
                    return '>1'
                else
                    return 0
                endif
            else
                return 1
            endif
        endif
    endif

    if next_indent <= this_indent
        return this_indent
    else
        return '>' . next_indent
    endif

endfunction

function! s:ToggleFolds() abort
    if foldclosed(line('.')) != -1
        normal! zO
    elseif foldlevel('.') != 0
        if g:anyfold_auto_reload
            call s:ReloadFolds(0)
        endif
        normal! zc
    endif
endfunction

function! s:ReloadFolds(force) abort
    if &modified
        if a:force || line('$') != b:anyfold_numlines
            let b:anyfold_numlines = line('$')

            if g:anyfold_identify_comments
                unlockvar! b:anyfold_commentlines
                let b:anyfold_commentlines = s:MarkCommentLines()
                lockvar! b:anyfold_commentlines
            endif

            unlockvar! b:anyfold_indent_list
            let b:anyfold_indent_list = s:InitIndentList()
            lockvar! b:anyfold_indent_list

            setlocal foldexpr=GetIndentFold(v:lnum)
        endif
    endif
endfunction

function! s:echoLineIndent() abort
    echom GetIndentFold(line('.'))
endfunction

function! s:echoIndentList() abort
    echom b:anyfold_indent_list[line('.')-1]
endfunction

"----------------------------------------------------------------------------/
" Improved fold display
" Inspired by example code by Greg Sexton
" http://www.gregsexton.org/2011/03/improving-the-text-displayed-in-a-fold/
"----------------------------------------------------------------------------/
function! MinimalFoldText() abort
    let fs = v:foldstart
    while getline(fs) !~ '\w'
        let fs = nextnonblank(fs + 1)
    endwhile
    if fs > v:foldend
        let line = getline(v:foldstart)
    else
        let line = substitute(getline(fs), '\t', repeat(' ', &tabstop), 'g')
    endif

    let w = winwidth(0) - &foldcolumn - (&number ? 8 : 0)
    let foldSize = 1 + v:foldend - v:foldstart
    let foldSizeStr = " " . foldSize . " lines "
    let foldLevelStr = repeat("  +  ", v:foldlevel)
    let lineCount = line("$")
    let expansionString = repeat(" ", w - strwidth(foldSizeStr.line.foldLevelStr))
    return line . expansionString . foldSizeStr . foldLevelStr
endfunction

"----------------------------------------------------------------------------/
" Motion
"----------------------------------------------------------------------------/
function! s:JumpFoldStart(visual) abort
    if g:anyfold_auto_reload
        call s:ReloadFolds(0)
    endif
    if a:visual
        normal! gv
    endif

    if line('.') == 1
        call cursor(1,1)
        return
    endif

    let curr_line = line('.')-1
    let curr_foldlevel=b:anyfold_indent_list[line('.')-1]

    if b:anyfold_indent_list[curr_line-1] == curr_foldlevel
        let curr_foldlevel += -1
    endif

    while b:anyfold_indent_list[curr_line-1] > curr_foldlevel
        if curr_line == 1
            break
        endif
        let curr_line += -1
    endwhile

    call cursor(curr_line,1)

endfunction

function! s:JumpFoldEnd(visual) abort
    if g:anyfold_auto_reload
        call s:ReloadFolds(0)
    endif
    if a:visual
        normal! gv
    endif

    if line('.') == line('$')
        call cursor(line('$'),1)
        return
    endif

    let curr_line = line('.')+1
    let curr_foldlevel=b:anyfold_indent_list[line('.')-1]

    if b:anyfold_indent_list[curr_line-1] == curr_foldlevel
        let curr_foldlevel += -1
    endif

    while b:anyfold_indent_list[curr_line-1] > curr_foldlevel
        if curr_line == line('$')
            break
        endif
        let curr_line += 1
    endwhile

    call cursor(curr_line,1)

endfunction

function! s:JumpPrevFoldEnd(visual) abort
    if g:anyfold_auto_reload
        call s:ReloadFolds(0)
    endif
    if a:visual
        normal! gv
    endif
    normal! kzkj
endfunction

function! s:JumpNextFoldStart(visual) abort
    if g:anyfold_auto_reload
        call s:ReloadFolds(0)
    endif
    if a:visual
        normal! gv
    endif
    normal! zj
endfunction
