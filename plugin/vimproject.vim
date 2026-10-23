if exists('g:loaded_vimproject')
    finish
endif
let g:loaded_vimproject = 1

command! VimProjectOpen call vimproject#pick(1)
command! VimProjectCd call vimproject#pick(0)

augroup vimproject
    autocmd!
    autocmd VimEnter,DirChanged * call vimproject#record()
augroup END
