# Markdown / MDX Development Guide

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

**Markdown / MDX** is installed by default alongside Lua on a fresh setup.
Node.js must be on PATH for `mdx-analyzer` and Prettier. If Node.js is missing,
install it and select this bundle in **Dependencies & Toolchains** (`:LanguageManager`).
The menu starts with no checkboxes selected; check only the bundles or components
you want to install or uninstall.

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| Language server | `mdx_analyzer` / `mdx-analyzer` | Completion, diagnostics, and navigation for `.mdx` files |
| Formatter | `prettier` | Markdown and MDX formatting; no Prettier plugin required |
| Treesitter | `markdown`, `markdown_inline` | Markdown highlighting; JSX and MDX expressions have limited highlighting |

Restart Neovim after updating the configuration. `.mdx` files use the `mdx`
filetype so the dedicated language server can attach. Keep a `package.json` in
the project root for language-server project detection. For JavaScript type
information, install TypeScript in the project (`npm install --save-dev typescript`).

Formatting follows FoxVim's existing Prettier policy: add a project Prettier
configuration (such as `.prettierrc.json` containing `{}`), then use
`:FormatDocument` or save the file.

See [MDX Analyzer](https://github.com/mdx-js/mdx-analyzer) for project type-checking
and remark plugin settings.
