let s:base = {}

function! s:base.get_var(name, default) abort
    let v = 'reply_repl_' . self.path_name . '_' . a:name
    return get(b:, v, get(g:, v, a:default))
endfunction

function! s:base.executable() abort
    return self.get_var('executable', self.name)
endfunction

function! s:base.is_available() abort
    return executable(self.executable())
endfunction

function! s:base.get_command() abort
    return [self.executable()] +
         \ self.get_var('command_options', []) +
         \ get(self.context, 'cmdopts', [])
endfunction

function! s:base._on_exit(channel, exitval) abort
    call reply#log('exit_cb callback with status', a:exitval, 'for', self.name)

    if has_key(self.context, 'on_close')
        call self.context.on_close(self, a:exitval)
    endif

    if has_key(self, 'hooks') && has_key(self.hooks, 'on_close')
        call self.hooks.on_close(self, a:exitval)
    endif

    if a:exitval == 0
    elseif a:exitval == -1
        " https://github.com/vim/vim/blob/f9c3883b11b33f0c548df5e949ba59fde74d3e7b/src/os_unix.c#L5759
        call reply#log(self.name, "terminated by signal")
    else
        call reply#error("REPL '%s' exited with status %d", self.name, a:exitval)
    endif

    if self.running
        call self.stop()
    endif
endfunction

" context {
"   source?: string;
"   bufname?: string;
"   cmdopts?: string[];
" }
function! s:base.start(context) abort
    let self.context = a:context
    let self.running = v:false
    let cmd = self.get_command()
    if type(cmd) != v:t_list
        let cmd = [cmd]
    endif
    let bufnr = term_start(cmd, {
        \   'term_name' : 'reply: ' . self.name,
        \   'vertical' : 1,
        \   'term_finish' : 'open',
        \   'exit_cb' : self._on_exit,
        \ })
    call reply#log('Start terminal at', bufnr, 'with command', cmd)
    let self.term_bufnr = bufnr
    let self.running = v:true
endfunction

function! s:base.into_terminal_job_mode() abort
    if bufnr('%') ==# self.term_bufnr
        if mode() ==# 't'
            return
        endif
        " Start Terminal-Job mode if job is alive
        if &modifiable
            normal! i
        endif
        return
    endif

    let winnr = bufwinnr(self.term_bufnr)
    if winnr != -1
        execute winnr . 'wincmd w'
    else
        execute 'vertical sbuffer' self.term_bufnr
    endif

    if mode() ==# 'n' && &modifiable
        " Start Terminal-Job mode if job is alive
        normal! i
    endif
endfunction

" Note: Precondition: Terminal window must exists
function! s:base.send_string(str) abort
    if !self.running
        throw reply#error("REPL '%s' is no longer running", self.name)
    endif

    let str = a:str
    if str[-1] !=# "\n"
        let str .= "\n"
    endif
    " Note: Zsh distinguishes <NL> and <CR> and regards <NL> as <C-j>.
    " We always use <CR> as newline character.
    let str = substitute(str, "\n", "\<CR>", 'g')

    " Note: Need to enter Terminal-Job mode for updating the terminal window

    let prev_winnr = winnr()
    call self.into_terminal_job_mode()

    call term_sendkeys(self.term_bufnr, str)
    call reply#log('String was sent to', self.name, ':', str)

    if winnr() != prev_winnr
        execute prev_winnr . 'wincmd w'
    endif
endfunction

function! s:base.extract_input_from_terminal_buf(lines) abort
    if !has_key(self, 'prompt_start') || self.prompt_start is v:null || !has_key(self, 'prompt_continue')
        throw reply#error("REPL '%s' does not support :ReplRecv", self.name)
    endif

    let exprs = []
    let continuing = v:false
    for idx in range(len(a:lines))
        let line = a:lines[idx]

        let s = matchstr(line, self.prompt_start)
        if s !=# ''
            let line = substitute(line[len(s) :], '\s\+$', '', '')
            if has_key(self, 'ignore_input_pattern') && line =~# self.ignore_input_pattern
                continue
            endif
            if line !=# ''
                let exprs += [line]
            endif
            let continuing = v:true
            continue
        endif

        let s = matchstr(line, self.prompt_continue isnot v:null ? self.prompt_continue : self.prompt_start)
        if s !=# ''
            let exprs += [substitute(line[len(s) :], '\s\+$', '', '')]
            continue
        endif

        let continuing = v:false
    endfor

    return exprs
endfunction

function! s:base.extract_user_input() abort
    if !bufexists(self.term_bufnr)
        throw reply#error("Terminal buffer #d for REPL '%s' is no longer existing", self.term_bufnr, self.name)
    endif

    let lines = getbufline(self.term_bufnr, 1, '$')
    if lines == [] || lines == ['']
        throw reply#error("Terminal buffer #d for REPL '%s' is empty", self.term_bufnr, self.name)
    endif

    let exprs = self.extract_input_from_terminal_buf(lines)
    call reply#log('Extracted lines from terminal #', self.term_bufnr, exprs)

    return exprs
endfunction

function! s:base.stop() abort
    if !self.running
        return
    endif

    let self.running = v:false

    " Maybe needed: call term_setkill(a:repl.term_bufnr, 'term')
    if bufexists(self.term_bufnr)
        try
            execute 'bdelete!' self.term_bufnr
        catch /^Vim\%((\a\+)\)\=:E516/
            " When the buffer is already deleted, skip deleting it
        endtry
        call reply#log('Stopped terminal', self.name, 'at', self.term_bufnr)
    else
        call reply#log('Terminal buffer to close is not found for ', self.name, 'at', self.term_bufnr)
    endif
endfunction

" config {
"   name: string;
" }
function! reply#repl#base(name, ...) abort
    let config = get(a:, 1, {})
    let r = deepcopy(s:base)
    let r.name = a:name
    if has_key(config, 'prompt_start')
        let r.prompt_start = config.prompt_start
    endif
    if has_key(config, 'prompt_continue')
        let r.prompt_continue = config.prompt_continue
    endif
    if has_key(config, 'ignore_input_pattern')
        let r.ignore_input_pattern = config.ignore_input_pattern
    endif
    let r.path_name = substitute(a:name, '-', '_', 'g')
    return r
endfunction
