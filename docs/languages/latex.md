# LaTeX & BibTeX Guide

[Back to Wiki Index](../index.md) | [Back to Languages Overview](../languages.md)

Select **LaTeX / BibTeX** in `:LanguageManager` (also available in the Command
Palette) to install this optional bundle. Fresh installations remain Lua-only;
opening a `.tex` or `.bib` file does not install tools.

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| Language server | `texlab` | Completion, diagnostics and navigation for `tex`, `plaintex` and `bib` |
| Formatter | `latexindent` | Conform formatting for `tex` and `plaintex`; BibTeX uses Texlab's LSP formatter |
| Treesitter | `latex`, `bibtex` | Syntax highlighting and structure |
| Indentation | Two spaces | Fallback for TeX/BibTeX buffers; respects EditorConfig |

Use `:FormatDocument` to format manually. The existing format-on-save behavior
also applies once the tools are installed. Mason supplies standalone binaries
for Texlab and latexindent on supported desktop platforms; a separate Perl
installation is not required for Mason's latexindent binary.

## Building PDFs

The bundle installs editor tooling, not a TeX distribution. Install
[MiKTeX](https://miktex.org/download) or [TeX Live](https://www.tug.org/texlive/)
separately, and ensure `latexmk` and your TeX engine are on `PATH`. Some
distributions also require Perl for `latexmk`.

With Texlab attached, save the file and run `:LspTexlabBuild`, or run
`latexmk -pdf main.tex` in a terminal. Texlab does not build on save by default.
PDF viewing and forward/inverse search require a separately configured viewer.

`:FoxHealthCheck` and the Language Manager footer check `latexmk`, `pdflatex`
and `perl` on `PATH`. These checks report build dependencies without blocking
installation of the editor tools. They detect executables, not the installed TeX
packages or whether a full PDF build succeeds. TeX Live may bundle its own Perl;
a missing global `perl` command does not necessarily prevent that setup building.

## Windows and Linux

The bundle uses the same configuration on Windows and Linux. Mason provides both
tools for Windows x64 and Linux x64 with glibc (such as typical Ubuntu/Debian
installations). Texlab supports more targets, but Mason's latexindent package
currently has no Linux ARM, Linux musl/Alpine or Windows ARM asset. On those
platforms, install latexindent through your TeX distribution or system package
manager instead; Mason installation of that component may fail.

On Windows, install MiKTeX or TeX Live and ensure their binaries are on `PATH`.
MiKTeX's latexmk also needs a Perl installation, such as Strawberry Perl.
On Linux, install TeX Live, latexmk and Perl through your distribution's package
manager. Neovim, the tools and the TeX distribution must all be available in the
same environment (for example, all inside WSL when using Neovim in WSL).

All language settings live in `lua/fox/langs/latex/init.lua`. This bundle uses
FoxVim's existing LSP, formatting and Treesitter integrations.

References: [LazyVim's TeX extra](https://www.lazyvim.org/extras/lang/tex),
[Texlab configuration](https://github.com/latex-lsp/texlab/wiki/Configuration),
[Mason latexindent package](https://github.com/mason-org/mason-registry/blob/main/packages/latexindent/package.yaml).
