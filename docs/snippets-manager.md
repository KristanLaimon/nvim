# 📋 Snippets Manager (`:SnippetManager`)

The **FoxVim Snippet Manager** lets you create, edit, override, delete, and list snippets per language in standard **VSCode JSON format**, fully integrated into Neovim's `blink.cmp` autocompletion engine — plus **full IntelliSense** (validation, field hints, hover docs) while editing snippet files themselves.

---

## 🚀 Commands

| Command | Action |
| :--- | :--- |
| `:SnippetManager` / `:FoxSnippetManager` | Open the interactive Snippet Manager menu |
| `:FoxSnippetEdit [lang]` | Open (or create) the snippets file for a language, e.g. `:FoxSnippetEdit lua` |
| `:FoxSnippetAdd [lang]` | Interactively add a new snippet (prompts for name, prefix, body, description) |
| `:FoxSnippetReload` | Force reload snippet definitions in `blink.cmp` |

Access all these from **Command Palette** (`<C-S-p>`) → category **Snippets**.

---

## 🏁 Quickstart — Adding Your First Snippet

1. Open the Snippet Manager: press `<C-S-p>` and search **Snippet Manager**, or run `:FoxSnippetManager`.
2. Choose **"Edit Snippets for Current Filetype"** (uses whatever file you have open).
3. The `snippets/<lang>.json` file opens with IntelliSense active.
4. Add your snippet entry (see format below), save with `:w`.
5. Your snippet is **live immediately** — start typing the prefix in any file of that type.

---

## 📁 File Location & Directory Structure

```
nvim/
└── snippets/
    ├── snippets.schema.json   ← JSON Schema (enables IntelliSense in ALL snippet files)
    ├── lua.json
    ├── typescript.json
    ├── javascript.json
    ├── php.json
    ├── python.json
    └── ...                    ← one file per filetype, named by filetype
```

> [!TIP]
> The filetype name to use is exactly what Neovim reports as `vim.bo.filetype`. Common ones: `lua`, `typescript`, `javascript`, `typescriptreact`, `php`, `python`, `go`, `cs`, `html`, `css`, `sh`, `markdown`.
>
> Filetype often differs from file extension (`.js` → `javascript`, `.md` → `markdown`, `.cpp`/`.h` → `cpp`/`c`). Check current buffer's filetype with `:set filetype?`.

---

## 🧠 IntelliSense While Editing Snippet Files

Every file inside `snippets/` automatically gets **JSON Schema validation and completion** courtesy of `jsonls`. The schema file is at `snippets/snippets.schema.json`.

When you open a `snippets/<lang>.json` file you will have:
- ✅ **Field autocompletion** — `prefix`, `body`, `description`, `scope` suggested automatically.
- ✅ **Hover documentation** — hover over any key to see what it does.
- ✅ **Inline validation** — missing `prefix` or `body`? A squiggly underline tells you immediately.
- ✅ **Type checking** — `body` must be a string or array of strings, `prefix` must be a string or array.

To activate it manually if needed: `:LspRestart jsonls`.

---

## 📝 Snippet JSON Format Reference

Each snippet file is a JSON object where **each key is the snippet name** (shown in the completion menu description).

```json
{
  "$schema": "./snippets.schema.json",

  "Snippet Name (shown in docs)": {
    "prefix": "trigger",
    "body": [
      "first line ${1:placeholder}",
      "second line ${2}",
      "${0}"
    ],
    "description": "Shown in blink.cmp completion details"
  }
}
```

### Fields

| Field | Required | Type | Description |
| :--- | :---: | :--- | :--- |
| `prefix` | ✅ | `string` or `string[]` | Trigger word(s) that expand the snippet |
| `body` | ✅ | `string` or `string[]` | Lines of code to insert; use an array for multi-line |
| `description` | — | `string` | Displayed in the completion detail panel |
| `scope` | — | `string` | Extra language filter (usually not needed since file = language) |

---

## ⚡ Body Syntax — Tabstops, Placeholders & Variables

### Tabstops

Jump between tabstops with `<Tab>` / `<S-Tab>` after expanding a snippet.

| Syntax | Meaning |
| :--- | :--- |
| `${1}`, `${2}`, ... | Cursor jumps to each numbered stop in order |
| `${0}` | **Final** cursor position — always place this last |
| `${1:default}` | Tabstop with a pre-filled default value |
| `${1\|opt1,opt2,opt3\|}` | Tabstop with a dropdown choice list |

### Mirroring

Using the **same number** in multiple places makes them mirror — editing one updates all of them simultaneously:

```json
"body": [
  "class ${1:MyClass} {",
  "    -- Extends ${1:MyClass}",
  "    ${0}",
  "}"
]
```

### Built-in Variables

| Variable | Expands to |
| :--- | :--- |
| `$TM_FILENAME` | Current file name (`index.ts`) |
| `$TM_FILENAME_BASE` | File name without extension (`index`) |
| `$TM_DIRECTORY` | Directory of current file |
| `$TM_FILEPATH` | Full path of current file |
| `$CURRENT_YEAR` | e.g. `2026` |
| `$CURRENT_MONTH` | e.g. `08` |
| `$CURRENT_DATE` | e.g. `21` |
| `$LINE_COMMENT` | Language line comment prefix (`--`, `//`, `#`) |
| `$BLOCK_COMMENT_START` | Block comment start (`/*`, `{-`, etc.) |
| `$BLOCK_COMMENT_END` | Block comment end (`*/`, `-}`, etc.) |
| `$CLIPBOARD` | Current clipboard contents |
| `$RANDOM` | Random 6-digit number |
| `$UUID` | Random UUID |

---

## 📖 Full Examples

### Lua — Module with EmmyLua class annotation
```json
{
  "$schema": "./snippets.schema.json",
  "Lua Class": {
    "prefix": "class",
    "body": [
      "---@class ${1:ClassName}",
      "local ${1:ClassName} = {}",
      "${1:ClassName}.__index = ${1:ClassName}",
      "",
      "---@return ${1:ClassName}",
      "function ${1:ClassName}.new(${2:opts})",
      "\tlocal self = setmetatable({}, ${1:ClassName})",
      "\t${0}",
      "\treturn self",
      "end",
      "",
      "return M"
    ],
    "description": "Standard Lua module template"
  }
}
```

---

## 🔄 Live Reload & Integration
Custom snippets are stored in VSCode format so they are compatible with standard snippet engines and `blink.cmp`. Whenever you update a snippet file via `:FoxSnippetEdit` or `:FoxSnippetAdd`, the snippets become immediately available during completion.
