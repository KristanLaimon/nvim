" FOX Blade syntax; implementation lives with the PHP language module.
if exists('b:current_syntax')
  finish
endif
lua require('fox.langs.php.blade').syntax()
