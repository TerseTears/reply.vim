if (exists('g:loaded_trepl') && g:loaded_trepl) || &cp
    finish
endif

command! -nargs=0 Repl call trepl#command#start()
command! -nargs=0 -bang ReplStop call trepl#command#stop(<bang>0)
command! -nargs=+ ReplSend call trepl#command#send(<q-args>)

let g:loaded_trepl = 1
