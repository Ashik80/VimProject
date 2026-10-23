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
    catch
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
        if len(selection) != 1 || !isdirectory(selection[0])
            call s:Warn('The selected project directory no longer exists.')
            return
        endif
        if a:state.create
            let marker = selection[0] . '/.project'
            if getftype(marker) ==# ''
                call writefile([], marker, 'a')
            elseif !filereadable(marker)
                throw 'Cannot create project marker: ' . marker
            endif
        endif
        call vimproject#cd(selection[0])
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

function! vimproject#pick() abort
    let registry = s:Registry()
    if !filereadable(registry) || empty(readfile(registry))
        call s:Warn('No projects recorded yet.')
        return
    endif
    call s:Pick('fzf --no-multi < ' . shellescape(registry), 0)
endfunction

function! vimproject#create(command) abort
    call s:Pick('(' . a:command . "\n) | fzf --no-multi", 1)
endfunction

function! s:Pick(command, create) abort
    if !executable('fzf')
        call s:Warn('fzf is not installed.')
        return
    endif
    if !has('nvim') && (!has('terminal') || !has('job'))
        call s:Warn('Vim needs terminal and job support.')
        return
    endif
    let state = {'window': win_getid(), 'output': tempname(), 'buffer': -1, 'create': a:create}
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
