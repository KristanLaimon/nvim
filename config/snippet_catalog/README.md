# Bundled snippet data

This is an attributed resource snapshot of rafamadriz/friendly-snippets at
`b4d01b0fdf3c9a549961c2f9ffe8dc09be166219`, matching FoxVim's previous lockfile.
Source: https://github.com/rafamadriz/friendly-snippets/tree/b4d01b0fdf3c9a549961c2f9ffe8dc09be166219

Copyright (c) 2021 Rafael Madriz and contributors. The MIT license is preserved
in `../../licenses/friendly-snippets.txt`. The JSON files are upstream snippet
resources, not newly authored FOX code. All 143 snippet files are kept unchanged;
the manifest preserves every original language alias and contribution order.

FoxVim's loader lives in `lua/fox/lsp/snippets.lua`. Blink and Neovim supply
expansion, variables, placeholders, mirrors and tabstop navigation. Custom
snippets remain in `config/snippets/`; do not edit the bundled defaults to
customize a trigger. A custom trigger takes precedence over bundled defaults.

Updates are manual: review the upstream resource diff and license, record the
new source commit here, update the manifest and run the snippet coverage and
real Blink integration checks. No network fetch or toolchain installation occurs
when loading snippets. No upstream plugin runtime is bundled.
