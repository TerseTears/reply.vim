let s:repl = reply#repl#base({'name' : 'go-pry'})

function! s:repl.executable() abort
    return self.get_var('executable', 'go-pry')
endfunction

function! reply#repl#go_pry#new() abort
    return deepcopy(s:repl)
endfunction
