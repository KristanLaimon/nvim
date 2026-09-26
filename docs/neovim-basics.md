# 🌱 Neovim Basics

[← Back to Wiki Index](index.md)

Never used Vim or Neovim before? Start here — the rest of this wiki assumes you
know the words on this page. It's a 5-minute read, not a manual.

---

## 🧠 The one idea that explains everything else: Modes

Neovim is a **modal** editor — the same keys do different things depending on
which "mode" you're in. This trips up everyone coming from VS Code or Notepad,
where typing always just... types.

| Mode | What it's for | How you get there |
| :--- | :--- | :--- |
| **Normal** | Moving around, deleting, the mode you start in | `<Esc>` from anywhere |
| **Insert** | Typing text, like a normal editor | `i` (insert before cursor) from Normal mode |
| **Visual** | Selecting text | `v` (character) or `V` (line) from Normal mode |
| **Command-line** | Running `:` commands like `:w` (save) | `:` from Normal mode |
| **Terminal** | A real shell running inside a window | Opens automatically in this config's terminal panels (`<C-;>`) |

**If you're ever confused about what will happen when you type, press `<Esc>`
first.** That always returns you to Normal mode, which is the safe, "nothing is
being typed into the file" default. This config also remaps `<C-s>`, `<C-z>`,
`<C-c>`/`<C-v>` etc. to work the same in every mode (see
[keybinds.md](keybinds.md)) specifically to soften this — but knowing *why*
`i` and `<Esc>` matter will save you the most confusion.

---

## 🪟 Buffers, windows, and tabs

These three words mean different things in Neovim than they do in a browser:

- **Buffer** = a file loaded into memory. You can have 30 buffers open and see
  none of them.
- **Window** = a viewport on screen showing one buffer. Split your screen and
  you have 2 windows, possibly showing the same buffer twice.
- **Tab** = a saved arrangement of windows. Not "one file per tab" like a
  browser — closer to a whole desktop layout you can switch between.

In this config: `<C-h>`/`<C-l>` moves focus between windows,
`gt`/`<A-l>`/`<A-Right>` cycles buffers, `<C-w>` closes the current buffer. Full
list in [keybinds.md](keybinds.md#🪟-windows-splits--buffers).

---

## ⌨️ The leader key

You'll see `<leader>` all over this wiki. It's just a prefix key that means
"and now a shortcut" — in this config it's mapped to `<Space>`. So
`<leader>ff` means: press `Space`, then `f`, then `f`. It exists because Vim
already uses almost every single unprefixed key for something, so custom
shortcuts need a dedicated prefix that's guaranteed free.

---

## 🐾 This config's own convention: `Ctrl+Shift+<Letter>` panels

On top of standard Vim, this config adds floating-window "panels" — Git Center,
Task Runner, this Wiki — each opened with `Ctrl+Shift+<a letter that matches
the name>`: `<C-S-g>` Git, `<C-S-t>` Tasks, `<C-S-f>` Files, `<C-S-d>` this
Wiki (Docs), and so on. Full table:
[keybinds.md § Key Shortcuts at a Glance](index.md#🚀-key-shortcuts-at-a-glance).

**Terminal heads-up:** some terminals (plain PowerShell/`conhost`, older
Windows Terminal) can't tell `Ctrl+D` and `Ctrl+Shift+D` apart — they only
report "Ctrl is held," not Shift, for letter keys. If a `Ctrl+Shift+X` panel
ever does nothing, every one of them also has a `<leader>` fallback and a `:`
command (e.g. `<leader>?` and `:FoxWiki` both open this wiki) that work
everywhere regardless of what your terminal reports.

---

## 🔎 `:` commands and `:help`

Anything starting with `:` is a command-line command, typed in Command-line
mode. `:w` saves, `:q` quits, `:e path/to/file` opens a file. Every plugin in
this config adds its own, always shown starting with a capital letter to tell
them apart from built-ins — e.g. `:FoxWiki`, `:TaskRestart`, `:WorkspaceSave`.

Neovim's own manual is installed locally and searchable: `:help`, or
`<leader>fh` in this config to fuzzy-search it. It's long, but it's the actual
source of truth for anything not specific to this config.

---

## 🆘 Forgot a shortcut?

Press `?` or `<F1>` in almost any window in this config — it shows a
context-aware cheatsheet for whatever you're currently looking at, so you
don't need to keep this wiki open in a split. `<C-S-p>` opens a fuzzy-searchable
Command Palette of every registered command if you know roughly what you want
but not the key.

---

## ➡️ Where to go next

- [Installation & Dependencies](installation.md) — first-time setup
- [Keybinds Reference](keybinds.md) — the full shortcut list, now that the
  column headers (`n`, `i`, `v`, `t` = Normal/Insert/Visual/Terminal mode) make
  sense
- [How-To & Customization Guide](how-to-customize-editor.md) — change or add
  anything in this config yourself, with real examples
