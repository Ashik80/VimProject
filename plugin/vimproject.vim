if exists('g:loaded_vimproject')
    finish
endif
let g:loaded_vimproject = 1

command! VimProjectOpen call vimproject#pick()
command! -nargs=1 -complete=dir VimProjectCd call vimproject#cd(<f-args>)

augroup vimproject
    autocmd!
    autocmd VimEnter,DirChanged * call vimproject#record()
augroup END
