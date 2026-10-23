function! s:Registry() abort
    return has('nvim') ? stdpath('config') . '/.projects' : expand('~/.vim/.projects')
endfunction

function! s:Warn(message) abort
    echohl WarningMsg
    echomsg 'VimProject: ' . a:message
    echohl None
endfunction

function! vimproject#record(...) abort
    let directory = a:0 ? a:1 : getcwd()
    if !isdirectory(directory . '/.git') && !filereadable(directory . '/.project')
        return
    endif
    if directory =~# "[\r\n]"
        call s:Warn('Cannot save a directory containing a newline.')
        return
    endif
    try
        let registry = s:Registry()
        let projects = filereadable(registry) ? readfile(registry) : []
        call mkdir(fnamemodify(registry, ':h'), 'p')
        let ignore = fnamemodify(registry, ':h') . '/.gitignore'
        let rules = filereadable(ignore) ? readfile(ignore) : []
        if index(rules, '/.projects') < 0
            call writefile(rules + ['/.projects'], ignore)
        endif
        if index(projects, directory) < 0
            call writefile([directory], registry, 'a')
        endif
    catch
        call s:Warn(v:exception)
    endtry
endfunction

function! vimproject#cd(directory) abort
    let directory = expand(a:directory)
    if !isdirectory(directory)
        call s:Warn('The directory does not exist: ' . directory)
        return
    endif
    let directory = fnamemodify(directory, ':p:h')
    call vimproject#record(directory)
    try
        execute 'cd ' . fnameescape(directory)
        execute 'edit ' . fnameescape(directory)
        return 1
    catch
        call s:Warn(v:exception)
    endtry
endfunction

function! vimproject#term() abort
    let directory = getcwd()
    if !isdirectory(directory . '/.git') && !filereadable(directory . '/.project')
        call vimproject#pick('term')
        return
    endif
    if !has('nvim') && (!has('terminal') || !has('job'))
        call s:Warn('Vim needs terminal and job support.')
        return
    endif
    call vimproject#record()
    let window = win_getid()
    let buffer = -1
    try
        for info in getbufinfo()
            if getbufvar(info.bufnr, 'vimproject_root', '') !=# directory
                continue
            endif
            let running = has('nvim')
                        \ ? jobwait([getbufvar(info.bufnr, 'terminal_job_id')], 0)[0] == -1
                        \ : term_getstatus(info.bufnr) =~# 'running'
            if !running
                execute 'silent! bwipeout! ' . info.bufnr
                break
            endif
            let windows = win_findbuf(info.bufnr)
            if empty(windows)
                execute 'botright sbuffer ' . info.bufnr
                execute 'resize ' . (&lines / 2)
            else
                call win_gotoid(windows[0])
            endif
            startinsert
            return
        endfor
        botright new
        execute 'resize ' . (&lines / 2)
        let buffer = bufnr('%')
        if has('nvim')
            if termopen([&shell], {'cwd': directory}) <= 0
                throw 'Could not start project shell.'
            endif
        elseif term_start([&shell], {'curwin': 1, 'cwd': directory}) <= 0
            throw 'Could not start project shell.'
        endif
        setlocal bufhidden=hide
        execute 'file ' . fnameescape(fnamemodify(directory, ':t') . '-shell')
        let b:vimproject_root = directory
        startinsert
    catch
        if buffer > 0 && bufexists(buffer)
            execute 'silent! bwipeout! ' . buffer
        endif
        call win_gotoid(window)
        call s:Warn(v:exception)
    endtry
endfunction

function! s:Finish(state, status, timer) abort
    try
        let selection = filereadable(a:state.output) ? readfile(a:state.output) : []
        if bufexists(a:state.buffer)
            execute 'silent! bwipeout! ' . a:state.buffer
        endif
        if !win_gotoid(a:state.window)
            return
        endif
        if a:status != 0
            if a:status != 1 && a:status != 130
                call s:Warn('fzf failed (exit ' . a:status . ').')
            endif
            return
        endif
        if len(selection) != 1
            return
        endif
        if a:state.action ==# 'remove'
            echo 'Remove project "' . selection[0] . '" from the list and delete its .project file? [y/N] '
            let answer = getcharstr()
            echo ''
            if answer ==? 'y'
                let registry = s:Registry()
                let projects = readfile(registry)
                let marker = selection[0] . '/.project'
                if getftype(marker) !=# '' && delete(marker) != 0
                    throw 'Cannot remove project marker: ' . marker
                endif
                call filter(projects, 'v:val !=# selection[0]')
                call writefile(projects, registry)
            endif
            return
        endif
        if !isdirectory(selection[0])
            call s:Warn('The selected project directory no longer exists.')
            return
        endif
        if a:state.action ==# 'create' && !isdirectory(selection[0] . '/.git')
            let marker = selection[0] . '/.project'
            if getftype(marker) ==# ''
                call writefile([], marker, 'a')
            elseif !filereadable(marker)
                throw 'Cannot create project marker: ' . marker
            endif
        endif
        if vimproject#cd(selection[0]) && a:state.action ==# 'term'
            call vimproject#term()
        endif
    catch
        call s:Warn(v:exception)
    finally
        call delete(a:state.output)
    endtry
endfunction

function! s:Exited(state, job, status, ...) abort
    " Defer cleanup until the terminal has finished processing its exit.
    call timer_start(0, function('s:Finish', [a:state, a:status]))
endfunction

function! vimproject#pick(...) abort
    let registry = s:Registry()
    if !filereadable(registry) || empty(readfile(registry))
        call s:Warn('No projects recorded yet.')
        return
    endif
    call s:Pick('fzf --no-multi < ' . shellescape(registry), a:0 ? a:1 : 'open')
endfunction

function! vimproject#create(command) abort
    call s:Pick('(' . a:command . "\n) | fzf --no-multi", 'create')
endfunction

function! s:Pick(command, action) abort
    if !executable('fzf')
        call s:Warn('fzf is not installed.')
        return
    endif
    if !has('nvim') && (!has('terminal') || !has('job'))
        call s:Warn('Vim needs terminal and job support.')
        return
    endif
    let state = {'window': win_getid(), 'output': tempname(), 'buffer': -1, 'action': a:action}
    let command = [&shell, &shellcmdflag, a:command . ' > ' . shellescape(state.output)]
    try
        if has('nvim')
            let state.buffer = nvim_create_buf(v:false, v:true)
            let width = max([1, min([&columns - 2, float2nr(&columns * 0.8)])])
            let height = max([1, min([&lines - 4, float2nr(&lines * 0.8) - 5])])
            call nvim_open_win(state.buffer, v:true, {
                        \ 'relative': 'editor', 'width': width, 'height': height,
                        \ 'col': max([0, (&columns - width) / 2 - 1]),
                        \ 'row': max([0, (&lines - height) / 2 - 1]),
                        \ 'style': 'minimal', 'border': 'single'})
            setlocal winhighlight=Normal:Normal,FloatBorder:Normal
            let job = termopen(command, {'on_exit': function('s:Exited', [state])})
            if job <= 0
                throw 'Could not start fzf.'
            endif
        else
            botright new
            resize 12
            let state.buffer = term_start(command, {'curwin': 1, 'exit_cb': function('s:Exited', [state])})
            if state.buffer <= 0
                let state.buffer = bufnr('%')
                throw 'Could not start fzf.'
            endif
        endif
        startinsert
    catch
        if state.buffer > 0 && bufexists(state.buffer)
            execute 'silent! bwipeout! ' . state.buffer
        endif
        call win_gotoid(state.window)
        call delete(state.output)
        call s:Warn(v:exception)
    endtry
endfunction
