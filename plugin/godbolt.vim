function s:complete(_a, _b, _c)
    return ['fzf', 'fzy', 'skim', 'telescope']
endfunction

command -bang -nargs=0 -range=% Godbolt lua require("godbolt").godbolt(<line1>, <line2>, "compiler-explorer", '<bang>' == '!')
command -bang -nargs=1 -range=% -complete=customlist,s:complete GodboltCompiler lua require("godbolt").godbolt(<line1>, <line2>, "compiler-explorer", '<bang>' == '!', <f-args>)
command -bang -nargs=0 -range=% GodboltAsmParser lua require("godbolt").godbolt(<line1>, <line2>, "asm-parser", '<bang>' == '!')
