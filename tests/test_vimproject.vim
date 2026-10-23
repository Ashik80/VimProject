set nomore
execute 'set runtimepath^=' . fnameescape($VIMPROJECT_ROOT)
runtime plugin/vimproject.vim

let s:base = $HOME . '/projects'
let s:git = s:base . '/git project'
let s:marker = s:base . '/marker project'
let s:plain = s:base . '/plain'
call mkdir(s:git . '/.git', 'p')
call mkdir(s:marker, 'p')
call writefile([], s:marker . '/.project')
call mkdir(s:plain, 'p')
let s:registry = has('nvim') ? $HOME . '/.config/nvim/.projects' : $HOME . '/.vim/.projects'
let s:ignore = fnamemodify(s:registry, ':h') . '/.gitignore'
call mkdir(fnamemodify(s:registry, ':h'), 'p')
call writefile(['*.swp'], s:ignore, 'b')

function! s:WaitForPicker() abort
    let attempts = 0
    while &buftype ==# 'terminal' && attempts < 100
        sleep 20m
        let attempts += 1
    endwhile
    call assert_notequal('terminal', &buftype, 'picker should finish and close')
endfunction

try
    call assert_equal(2, exists(':VimProjectOpen'))
    call assert_equal(2, exists(':VimProjectCd'))
    execute 'cd ' . fnameescape(s:git)
    doautocmd VimEnter
    call assert_true(filereadable(s:registry), 'startup should record a project')
    if filereadable(s:registry)
        call assert_equal([s:git], readfile(s:registry))
        call assert_equal(['*.swp', '/.projects'], readfile(s:ignore), 'ignore the registry without losing existing rules')
        execute 'cd ' . fnameescape(s:marker)
        execute 'cd ' . fnameescape(s:plain)
        execute 'cd ' . fnameescape(s:git)
        call assert_equal([s:git, s:marker], readfile(s:registry), 'record both markers, not plain dirs or duplicates')
        call assert_equal(['*.swp', '/.projects'], readfile(s:ignore), 'ignore rule should not be duplicated')

        let $FZF_DEFAULT_OPTS = '--filter=' . shellescape(s:marker)
        let s:buffer = bufnr('%')
        VimProjectCd
        call s:WaitForPicker()
        call assert_equal(s:marker, getcwd(), 'Cd should change cwd')
        call assert_equal(s:buffer, bufnr('%'), 'Cd should preserve the original buffer')

        call setline(1, 'unsaved changes')
        setlocal modified
        set nohidden
        let $FZF_DEFAULT_OPTS = '--filter=' . shellescape(s:git)
        VimProjectOpen
        call s:WaitForPicker()
        call assert_equal('unsaved changes', getline(1), 'Open must not discard unsaved changes')
        call assert_equal(s:marker, getcwd(), 'failed edit must not change cwd')
        setlocal nomodified

        VimProjectOpen
        call s:WaitForPicker()
        call assert_equal(s:git, getcwd(), 'Open should change cwd')
        call assert_equal(s:git, substitute(expand('%:p'), '/$', '', ''), 'Open should edit the selected directory')

        let $FZF_DEFAULT_OPTS = '--filter=no-such-project'
        VimProjectCd
        call s:WaitForPicker()
        call assert_equal(s:git, getcwd(), 'no match must not change cwd')

        let s:special = s:base . '/quote'' | project'
        call mkdir(s:special . '/.git', 'p')
        execute 'cd ' . fnameescape(s:special)
        execute 'cd ' . fnameescape(s:plain)
        let $FZF_DEFAULT_OPTS = '--filter=quote'
        VimProjectCd
        call s:WaitForPicker()
        call assert_equal(s:special, getcwd(), 'paths must not be interpreted as commands')

        call delete(s:special, 'rf')
        execute 'cd ' . fnameescape(s:plain)
        VimProjectCd
        call s:WaitForPicker()
        call assert_equal(s:plain, getcwd(), 'deleted project must not change cwd')
        call assert_equal(3, len(readfile(s:registry)), 'selection should not duplicate entries')
    endif
catch
    call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry

if !empty(v:errors)
    call writefile(v:errors, $HOME . '/test-errors')
    cquit
endif
qa!
