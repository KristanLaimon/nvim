if exists('b:did_indent')
  finish
endif
let b:did_indent = 1
setlocal autoindent
setlocal indentexpr=v:lua.require'fox.langs.php.blade'.indent(v:lnum)
setlocal indentkeys=o,O,0<,0},0=@else,0=@end,0=@empty
let b:fox_indentexpr = &l:indentexpr
let b:undo_indent = 'setlocal autoindent< indentexpr< indentkeys< | unlet! b:fox_indentexpr'
