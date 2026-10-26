# 📋 Snippets Guide: How to Create Snippets & Identify Language Names

This guide explains how to create custom snippets in **FoxVim** using standard **VSCode JSON format** and how to find the exact `<lang>` filetype identifier Neovim expects for `<lang>.json` files inside the `config/snippets/` directory.

---

## 🔍 How to Identify Neovim's `<lang>` Identifier

Snippets in FoxVim are stored as `config/snippets/<lang>.json`. The `<lang>` string MUST match the exact **Neovim Filetype** (`vim.bo.filetype`), which is not always the same as the file extension.

### Method 1: Ask Neovim Directly (Recommended)
Open any file in Neovim and run one of these commands:
```vim
:set filetype?
```
or in Lua command line:
```vim
:lua print(vim.bo.filetype)
```
The output string (e.g. `typescriptreact`, `cs`, `sh`, `ps1`, `cpp`) is the exact name for `<lang>.json`.

### Method 2: Use the Built-in Snippet Manager Commands
FoxVim automatically auto-detects the current file's filetype identifier:
- Run `:FoxSnippetEdit` (or `:SnippetManager` → *Edit Snippets for Current Filetype*).
- Neovim will automatically resolve and open `config/snippets/<lang>.json` for the file you are currently editing.

---

## 🌐 Common Language Identifier Reference Table

| Language / Technology | File Extension(s) | Neovim `<lang>` Identifier | Snippet File Path |
| :--- | :--- | :--- | :--- |
| **Lua** | `.lua` | `lua` | `config/snippets/lua.json` |
| **TypeScript** | `.ts` | `typescript` | `config/snippets/typescript.json` |
| **TypeScript React (TSX)** | `.tsx` | `typescriptreact` | `config/snippets/typescriptreact.json` |
| **JavaScript** | `.js`, `.mjs`, `.cjs` | `javascript` | `config/snippets/javascript.json` |
| **JavaScript React (JSX)** | `.jsx` | `javascriptreact` | `config/snippets/javascriptreact.json` |
| **Svelte** | `.svelte` | `svelte` | `config/snippets/svelte.json` |
| **Python** | `.py` | `python` | `config/snippets/python.json` |
| **PHP** | `.php` | `php` | `config/snippets/php.json` |
| **Blade (Laravel)** | `.blade.php` | `blade` | `config/snippets/blade.json` |
| **Go** | `.go` | `go` | `config/snippets/go.json` |
| **C# / .NET** | `.cs` | `cs` | `config/snippets/cs.json` |
| **C** | `.c`, `.h` | `c` | `config/snippets/c.json` |
| **C++** | `.cpp`, `.hpp`, `.cc` | `cpp` | `config/snippets/cpp.json` |
| **Rust** | `.rs` | `rust` | `config/snippets/rust.json` |
| **Zig** | `.zig` | `zig` | `config/snippets/zig.json` |
| **Shell / Bash** | `.sh`, `.bash`, `.zsh` | `sh` | `config/snippets/sh.json` |
| **PowerShell** | `.ps1`, `.psm1`, `.psd1` | `ps1` | `config/snippets/ps1.json` |
| **HTML** | `.html`, `.htm` | `html` | `config/snippets/html.json` |
| **CSS** | `.css` | `css` | `config/snippets/css.json` |
| **SCSS / SASS** | `.scss`, `.sass` | `scss` | `config/snippets/scss.json` |
| **JSON / JSONC** | `.json`, `.jsonc` | `json`, `jsonc` | `config/snippets/json.json` |
| **YAML** | `.yaml`, `.yml` | `yaml` | `config/snippets/yaml.json` |
| **TOML** | `.toml` | `toml` | `config/snippets/toml.json` |
| **Markdown** | `.md` | `markdown` | `config/snippets/markdown.json` |
| **Dockerfile** | `Dockerfile`, `.dockerfile` | `dockerfile` | `config/snippets/dockerfile.json` |
| **SQL** | `.sql` | `sql` | `config/snippets/sql.json` |

---

## 📝 How to Create Snippets

### 1. Snippet File Structure
Every file in `config/snippets/` is a JSON object where **each top-level key is the snippet name** (displayed in completion menus). Include `"$schema": "./snippets.schema.json"` at the top for live IntelliSense, autocompletion, and validation while editing snippets.

```json
{
  "$schema": "./snippets.schema.json",

  "Console Log": {
    "prefix": "clog",
    "body": [
      "console.log('${1:label}:', ${2:value});",
      "${0}"
    ],
    "description": "Log value with label to browser/node console"
  }
}
```

### 2. Snippet Schema Property Reference

| Property | Required | Type | Description |
| :--- | :---: | :--- | :--- |
| `prefix` | ✅ | `string` or `string[]` | Trigger word(s) typed in the editor to activate completion |
| `body` | ✅ | `string` or `string[]` | Code content inserted on expansion (use array of strings for multi-line) |
| `description` | — | `string` | Explanation displayed in the doc detail popup |
| `scope` | — | `string` | Sub-language filter (optional) |

---

## ⚡ Body Formatting & Variables

### Tabstops (`$1`, `$2`, `$0`)
Navigate between tabstops using `<Tab>` (forward) and `<S-Tab>` (backward).
- `$1`, `$2`, `$3` define the cursor stopping sequence.
- `$0` defines the **final cursor position** after exiting all tabstops.

```json
"body": [
  "function ${1:fnName}(${2:params}) {",
  "\t${0}",
  "}"
]
```

### Placeholders (`${1:default_text}`)
Placeholders provide default text that can be edited immediately or accepted by pressing `<Tab>`.
```json
"body": "const [${1:state}, set${1/(.*)/${1:/capitalize}/}] = useState(${2:initialState});"
```

### Choice Pickers (`${1|option1,option2,option3|}`)
Renders a choices dropdown selection during snippet expansion.
```json
"body": "const mode = '${1|development,staging,production|}';"
```

### Useful VSCode Snippet Variables

| Variable | Output | Example |
| :--- | :--- | :--- |
| `$TM_FILENAME` | Active filename with extension | `main.ts` |
| `$TM_FILENAME_BASE` | Active filename without extension | `main` |
| `$TM_DIRECTORY` | Absolute path of current folder | `/home/user/project/src` |
| `$CLIPBOARD` | Current system clipboard content | *(pasted text)* |
| `$CURRENT_YEAR` | Current 4-digit year | `2026` |
| `$CURRENT_MONTH` | Current 2-digit month | `09` |
| `$LINE_COMMENT` | Language line comment symbol | `//` or `#` or `--` |

---

## 🛠️ Snippet Commands in FoxVim

You can manage all snippets directly from Neovim:

| Command | Palette Entry (`<C-S-p>`) | Action |
| :--- | :--- | :--- |
| `:SnippetManager` | **Snippets: Open Snippet Manager** | Opens interactive GUI menu |
| `:FoxSnippetEdit [lang]` | **Snippets: Edit Snippets for Language** | Opens `config/snippets/<lang>.json` |
| `:FoxSnippetAdd [lang]` | **Snippets: Add New Snippet** | Interactive prompt to create a snippet |
| `:FoxSnippetReload` | **Snippets: Reload Snippets** | Hot-reloads definitions into `blink.cmp` |

Saved snippet changes apply **immediately** upon saving (`:w`) without restarting Neovim!

## Bundled defaults and overrides

The complete attributed default catalog is stored separately in
`../snippet_catalog/` (license: `../../licenses/friendly-snippets.txt`). It is resource
data from friendly-snippets; FoxVim does not clone or load that plugin. Keep edits
in this directory: your prefixes take precedence over bundled suggestions.
Saving JSON files, using the manager or running `:FoxSnippetReload` rescans both
new and existing definitions without restarting Blink.
