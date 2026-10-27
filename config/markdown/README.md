# Browser resources

`page.html` and `preview.js` are FOX's local preview UI. The HTTP server and
Markdown renderer are original Lua modules in `lua/fox/markdown/`.

`mermaid.min.js` is an unmodified third-party browser bundle, **not a FOX rewrite**.
It was taken from the installed `iamcco/markdown-preview.nvim` resource
`app/_static/mermaid.min.js` at upstream commit
`a923f5fc5ba36a3b17e289dc35dc17f66d0548ee`.
SHA-256: `245a6d632e0acc9e4e40ff90f5fb9b35fddcc693cf9992aa50ea2fc8438d2ab4`.
Its embedded third-party license notices are preserved; Mermaid's MIT license
is in `licenses/mermaid.txt` (https://github.com/mermaid-js/mermaid/blob/develop/LICENSE).
No plugin, Node runtime, npm packages, CDN or CLI is needed to serve this file.

`markdown.css` is the unmodified GitHub-like stylesheet from the same plugin
commit (`app/_static/markdown.css`), originally from
https://github.com/iamcco/markdown.css. Its MIT license is preserved in
`licenses/markdown-preview-style.txt`. It is a browser asset, not a dependency
on the former server or plugin.

`mona-sans.woff2` and `mona-sans-italic.woff2` are GitHub's unmodified Mona Sans
variable fonts (`MonaSansVF[opsz,wght].woff2` and
`MonaSansVF-Italic[opsz,wght].woff2` under `fonts/webfonts/variable/`), from
https://github.com/github/mona-sans at commit
`4bc6ba8b354c36b4fb66d32cd67b4c1f2beb0a06`. Their SIL Open Font License is in
`licenses/mona-sans.txt`. The UI uses Primer's font stack with this local font
first: https://primer.style/product/primitives/typography/.
