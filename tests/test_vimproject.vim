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

        let s:direct = $HOME . '/Documents'
        call mkdir(s:direct, 'p')
        call writefile([], s:direct . '/.project')
        VimProjectCd ~/Documents
        call assert_equal(s:direct, getcwd(), 'Cd should expand ~ and change cwd without a picker')
        call assert_equal(s:direct, substitute(expand('%:p'), '/$', '', ''), 'Cd should edit the directory')
        call assert_equal([s:git, s:marker, s:direct], readfile(s:registry), 'Cd should record a newly visited project')

        execute 'VimProjectCd ' . fnameescape(s:plain)
        call assert_equal(s:plain, getcwd(), 'Cd should also visit non-project directories')
        call assert_equal(s:plain, substitute(expand('%:p'), '/$', '', ''))
        call assert_equal([s:git, s:marker, s:direct], readfile(s:registry), 'Cd should not record non-project directories')
        execute 'VimProjectCd ' . fnameescape(s:marker)
        call assert_equal(s:marker, getcwd(), 'Cd should handle escaped spaces')

        VimProjectCd ~/missing-directory
        call assert_equal(s:marker, getcwd(), 'invalid directory should not change cwd')
        call assert_equal(3, len(readfile(s:registry)), 'invalid directory should not be recorded')

        enew
        call setline(1, 'unsaved changes')
        setlocal modified
        set nohidden
        let $FZF_DEFAULT_OPTS = '--filter=' . shellescape(s:git)
        VimProjectOpen
        call s:WaitForPicker()
        call assert_equal('unsaved changes', getline(1), 'Open must not discard unsaved changes')
        call assert_equal(s:git, getcwd(), 'Cd runs before edit, even when edit is blocked by unsaved changes')
        setlocal nomodified

        VimProjectOpen
        call s:WaitForPicker()
        call assert_equal(s:git, getcwd(), 'Open should change cwd')
        call assert_equal(s:git, substitute(expand('%:p'), '/$', '', ''), 'Open should edit the selected directory')

        let $FZF_DEFAULT_OPTS = '--filter=no-such-project'
        VimProjectOpen
        call s:WaitForPicker()
        call assert_equal(s:git, getcwd(), 'no match must not change cwd')

        let s:special = s:base . '/quote'' | project'
        call mkdir(s:special . '/.git', 'p')
        execute 'cd ' . fnameescape(s:special)
        execute 'cd ' . fnameescape(s:plain)
        let $FZF_DEFAULT_OPTS = '--filter=quote'
        execute 'VimProjectCd ' . fnameescape(s:special)
        call assert_equal(s:special, getcwd(), 'paths must not be interpreted as commands')
        call assert_equal(s:special, substitute(expand('%:p'), '/$', '', ''))

        call delete(s:special, 'rf')
        execute 'cd ' . fnameescape(s:plain)
        VimProjectOpen
        call s:WaitForPicker()
        call assert_equal(s:plain, getcwd(), 'deleted project must not change cwd')
        call assert_equal(4, len(readfile(s:registry)), 'selection should not duplicate entries')
    endif

    let s:created = s:base . '/new-project quote'' | dir'
    call mkdir(s:created, 'p')
    let s:producer = "printf '%s\\n' " . shellescape(s:plain) . ' ' . shellescape(s:created)
    let $FZF_DEFAULT_OPTS = '--filter=new-project'
    call VimProjectCreate(s:producer)
    call s:WaitForPicker()
    call assert_equal(s:created, getcwd(), 'Create should visit the selected directory')
    call assert_equal(s:created, substitute(expand('%:p'), '/$', '', ''))
    call assert_true(filereadable(s:created . '/.project'), 'Create should add a project marker')
    call assert_false(filereadable(s:plain . '/.project'), 'unselected directories must not be changed')
    let s:projects = readfile(s:registry)
    call assert_equal(s:created, s:projects[-1], 'Create should record the selected directory')

    call writefile(['keep existing contents'], s:created . '/.project')
    call VimProjectCreate(s:producer)
    call s:WaitForPicker()
    call assert_equal(['keep existing contents'], readfile(s:created . '/.project'), 'existing markers must not be overwritten')
    call assert_equal(s:projects, readfile(s:registry), 'creating twice must not duplicate the project')

    let s:shell = &shell
    set shell=/bin/bash
    call VimProjectCreate('directories=(' . shellescape(s:created) . "); printf '%s\\n' \"${directories[@]}\"")
    call s:WaitForPicker()
    let &shell = s:shell
    call assert_equal(s:created, getcwd(), 'Create should support Bash syntax when shell is Bash')
    call assert_equal(s:projects, readfile(s:registry))

    let $FZF_DEFAULT_OPTS = '--filter=no-such-project'
    call VimProjectCreate(s:producer)
    call s:WaitForPicker()
    call assert_equal(s:created, getcwd(), 'no match must not change cwd')
    call assert_false(filereadable(s:plain . '/.project'), 'no match must not create a marker')
    call assert_equal(s:projects, readfile(s:registry))

    let $FZF_DEFAULT_OPTS = '--filter=missing'
    call VimProjectCreate("printf '%s\\n' " . shellescape(s:base . '/missing'))
    call s:WaitForPicker()
    call assert_equal(s:created, getcwd(), 'invalid selection must not change cwd')
    call assert_equal(s:projects, readfile(s:registry))

    let s:blocked = s:base . '/blocked-project'
    call mkdir(s:blocked . '/.project', 'p')
    let $FZF_DEFAULT_OPTS = '--filter=blocked-project'
    call VimProjectCreate("printf '%s\\n' " . shellescape(s:blocked))
    call s:WaitForPicker()
    call assert_equal(s:created, getcwd(), 'failure to create a marker must not change cwd')
    call assert_equal(s:projects, readfile(s:registry))

    call delete(s:registry)
    let $FZF_DEFAULT_OPTS = '--filter=plain'
    call VimProjectCreate(s:producer)
    call s:WaitForPicker()
    call assert_equal(s:plain, getcwd(), 'Create should work without an existing registry')
    call assert_true(filereadable(s:plain . '/.project'))
    call assert_equal([s:plain], readfile(s:registry))

    call assert_equal(2, exists(':VimProjectRemove'))
    let s:projects = [s:plain, s:git, s:created, s:special]
    call writefile(s:projects, s:registry)
    let s:buffer = bufnr('%')
    let $FZF_DEFAULT_OPTS = '--filter=plain'
    call feedkeys('n', 't')
    VimProjectRemove
    call s:WaitForPicker()
    call assert_equal(s:projects, readfile(s:registry), 'No must leave the project list unchanged')
    call assert_true(filereadable(s:plain . '/.project'), 'No must preserve the marker')

    call feedkeys("\<CR>", 't')
    VimProjectRemove
    call s:WaitForPicker()
    call assert_equal(s:projects, readfile(s:registry), 'confirmation must default to No')

    call feedkeys("\<Esc>", 't')
    VimProjectRemove
    call s:WaitForPicker()
    call assert_equal(s:projects, readfile(s:registry), 'Esc must leave the project list unchanged')

    call feedkeys('y', 't')
    VimProjectRemove
    call s:WaitForPicker()
    call assert_equal(s:projects[1:], readfile(s:registry), 'Yes must remove only the selected entry')
    call assert_equal(s:plain, getcwd(), 'Remove must not change cwd or re-record the current project')
    call assert_equal(s:buffer, bufnr('%'), 'Remove must preserve the original buffer')
    call assert_true(isdirectory(s:plain), 'Remove must not delete the directory')
    call assert_equal('', getftype(s:plain . '/.project'), 'confirmed removal must delete the marker')

    let $FZF_DEFAULT_OPTS = '--filter=' . shellescape('!new-project quote')
    call feedkeys('y', 't')
    VimProjectRemove
    call s:WaitForPicker()
    call assert_equal([s:git, s:created], readfile(s:registry), 'Remove should also forget a deleted directory')

    let $FZF_DEFAULT_OPTS = '--filter=no-such-project'
    VimProjectRemove
    call s:WaitForPicker()
    call assert_equal([s:git, s:created], readfile(s:registry), 'no match must leave the list unchanged')

    call writefile([s:created], s:registry)
    let $FZF_DEFAULT_OPTS = '--filter=new-project'
    call feedkeys('y', 't')
    VimProjectRemove
    call s:WaitForPicker()
    call assert_equal([], readfile(s:registry), 'Remove should allow an empty project list')
    call assert_equal('', getftype(s:created . '/.project'), 'confirmed removal must delete a nonempty marker too')
    call assert_true(isdirectory(s:created), 'the project directory must remain')
    VimProjectRemove
    call assert_equal(s:buffer, bufnr('%'), 'an empty list should not open a picker')

    call writefile([s:blocked], s:registry)
    let $FZF_DEFAULT_OPTS = '--filter=blocked-project'
    call feedkeys('y', 't')
    VimProjectRemove
    call s:WaitForPicker()
    call assert_true(isdirectory(s:blocked . '/.project'), 'Remove must not delete a directory named .project')
    call assert_equal([s:blocked], readfile(s:registry), 'failure to delete the marker must preserve the registry entry')

    call writefile([s:git], s:registry)
    let $FZF_DEFAULT_OPTS = '--filter=' . shellescape(s:git)
    call feedkeys('y', 't')
    VimProjectRemove
    call s:WaitForPicker()
    call assert_equal([], readfile(s:registry), 'Remove must work when no marker exists')
    call assert_true(isdirectory(s:git . '/.git'), 'Remove must never delete .git')
catch
    call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry

if !empty(v:errors)
    call writefile(v:errors, $HOME . '/test-errors')
    cquit
endif
qa!
