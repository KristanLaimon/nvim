# 📚 Offline Documentation Store (`:DocManager`)

The **FoxVim Offline Documentation Store** enables full CRUD management and instant fuzzy searching of offline documentation for your programming languages, structured by language and version.

---

## 🚀 Key Commands

| Command | Action |
| :--- | :--- |
| `:DocManager` / `:FoxDocManager` | Open the main Offline Doc Manager UI menu |
| `:FoxDocSearch [query]` | Fuzzy search across all offline docs using Telescope live_grep |
| `:FoxDocView [lang] [version]` | Browse offline docs for a language & version (e.g. `:FoxDocView lua 5.4`) |
| `:FoxDocAdd [lang] [version] [topic]` | Create a new offline doc topic file with template |

Access all documentation commands via **Command Palette** (`<C-S-p>`) under the **Documentation** category.

---

## 📁 Storage Structure

Offline documentation is stored locally inside:
```
nvim/docs/offline/<language>/<version>/<topic>.md
```

### Examples:
- `nvim/docs/offline/lua/5.4/overview.md`
- `nvim/docs/offline/typescript/5.5/overview.md`
- `nvim/docs/offline/php/8.3/overview.md`
- `nvim/docs/offline/python/3.12/overview.md`

You can add any Markdown documentation files, cheat sheets, or API reference guides to these directories. They will be indexed for instant offline search and viewing.
