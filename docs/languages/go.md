# 🟦 Go Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

FoxVim provides a dedicated **Go** environment powered by `gopls`, `gofumpt`, `goimports`, and `delve` DAP debugging.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `gopls` | Official Go language server with integrated staticcheck analysis, inlay hints, and code lenses |
| **Linters** | `staticcheck`, `revive`, `golangci-lint` | Advanced static analysis & code style (SA/ST/QF/U rules) running alongside `go vet` |
| **Formatters (Conform)** | `goimports`, `gofumpt` | Automatic import organization and strict Go code formatting |
| **Treesitter Parsers** | `go`, `gomod`, `gowork`, `gosum` | Highlighting for Go source, `go.mod`, `go.work`, `go.sum` |
| **Autocompletion** | `blink.cmp` | Type completion, struct field hints, and snippet completion |
| **Debug Adapter (DAP)** | `delve` (local `fox.langs.go`) | Full Go debugger for main packages, single files, and test suites |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:FormatDocument` – Format active file using `goimports` and `gofumpt`.
* `:LanguageManager` – Install or uninstall the Go language bundle.

---

## 🐞 Debugger Profiles (`<F5>`)

The Delve adapter and these profiles live in `lua/fox/langs/go/init.lua`:

1. **Debug**: Debug the current Go file.
2. **Debug (Arguments)**: Prompt for program arguments; quoted values stay together.
3. **Debug (Arguments & Build Flags)**: Prompt for arguments and Go build flags.
4. **Debug Package**: Debug the current file's package directory.
5. **Attach**: Choose a local process to attach to.
6. **Debug test**: Build a test executable from the current file.
7. **Debug test (go.mod)**: Debug tests in the current package relative to the workspace.

Cancelling an arguments or build-flags prompt aborts the launch. Delve is installed
only when selected through the Go bundle in `:LanguageManager`. FoxVim uses its
native Mason executable when present, otherwise `dlv` from PATH. Windows launches
keep Delve attached to the parent process.
