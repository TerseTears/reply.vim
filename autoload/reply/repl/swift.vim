let s:repl = reply#repl#base({'name' : 'swift'})

function! s:repl.get_command() abort
    return [self.executable(), '-repl']
endfunction

function! reply#repl#swift#new() abort
    return deepcopy(s:repl)
endfunction
