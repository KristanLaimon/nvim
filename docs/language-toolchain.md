# Configure current LANGUAGE

Open a file and choose **Configure current LANGUAGE** from the Command Palette,
or run `:ConfigureCurrentLanguage`. The title follows the buffer's filetype, so
PHP and Blade can have separate selections.

| Key | Action |
|---|---|
| `j` / `k` | Move through the list |
| `Space` | Toggle the focused tool |
| `o` | Enable only the focused tool |
| `K` / `J` | Move an enabled tool earlier or later |
| `m` | Switch formatters between first available and running all in order |
| `e` | Open an existing native configuration, start one, or inspect editor defaults |
| `c` | Set comma-separated configuration filenames. Clear the input to return to native detection |
| `g` | Switch between project and global scope on the LSP and linter lists |
| `r` | Reset the tool selection at the current scope |
| `q` | Return to the cards |

Project selections live in `.foxnvim/toolchain.json`. Global selections live in
`stdpath('data')/toolchain.json`, typically `nvim-data/toolchain.json` on Windows.
A project selection replaces the global list for that filetype and category.
Selections do not install binaries. Standalone linters publish diagnostics when
you save. Multiple language servers can attach at once. LSP priority picks the
first selected server that can format when Conform falls back to an LSP.

`e` opens native files in a floating editor. Use `:w` to save and `:close` to
return. Biome uses `formatter.lineWidth`, Prettier uses `printWidth`, and
Blade Formatter uses `wrapLineLength`. LSP settings are JSON objects named
`lsp/<server>.json` under `.foxnvim` or `stdpath('data')`. FoxVim merges
them over server defaults, applying project values last. Native files always
belong to the project and are interpreted by the tool itself.

The manager checks custom filenames from the buffer directory upward, with a
project-root fallback. Tools with an explicit config adapter receive that path.
For LSPs the filename also determines the workspace root. For tools without a
config adapter, custom filenames control detection and the tool still handles
its own configuration lookup.

## Register a tool

Formatter rows come from `M.formatters_by_ft`. Server rows come from enabled
`M.lsp_config` entries and their resolved filetypes. Add optional metadata to
`M.toolchain[name]` in the owning language's `init.lua`.

- `files` lists native config filenames. If `template` provides starter text,
  the first filename is the default creation target unless `create` names
  another one. Existing files are opened verbatim.
- `config_args` takes an argument list with `$CONFIG` for the resolved path.
  Set `config_after_subcommand` when flags must come after a command such as
  `fix`. Use `config_env` for tools that accept the path via an environment variable.
- `diagnostics = true` puts a diagnostics-only LSP in the Linters list. It
  still runs through the LSP lifecycle.
- `lint` registers a standalone linter with `filetypes`, optional `command`
  (defaults to the tool name), `args`, optional `config_args`, and the
  `errorformat` string in `efm`. FoxVim appends the absolute source filename
  and parses the tool's output into buffer diagnostics.
