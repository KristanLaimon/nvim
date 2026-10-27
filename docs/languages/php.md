# 🐘 PHP & Laravel Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

FoxVim provides a complete development environment for **PHP** and **Laravel** applications, including Blade template highlighting, component autocompletion, Xdebug debugging, and automated code formatting.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `intelephense` | Serves both `.php` and `.blade.php` files; loaded with Laravel, PHPUnit & core stubs and a 5 MB file-index limit for Laravel Composer metadata |
| **Formatters (Conform)** | `pint`, `php-cs-fixer`, `blade-formatter` | `pint` or `php-cs-fixer` for PHP; `blade-formatter` for `.blade.php` |
| **Treesitter Parsers** | `php`, `phpdoc`, `blade` | Syntax trees for highlighting, indentation, and structure |
| **Autocompletion** | `blink.cmp` + `fox.langs.php.laravel` | Intelephense LSP + Laravel routes, views, components, livewire, config, env, & translations |
| **Debug Adapter (DAP)** | `php-debug-adapter` (Xdebug) | Listening on port `9003` for web server & CLI debugging |
| **Local Vendor Scripts** | `vendor/bin` | Automatically prepended to `PATH` on launch & directory change for local Composer scripts |

The local Laravel index supplies routes, views, components, Livewire, config, environment, translation and Inertia references through Blink and buffer-local `gf`. Indexes are scoped to the nearest `artisan` project, expire after five seconds, and clear on writes or `:BladeNavClearCache`. PHP Artisan is queried asynchronously for runtime routes and registered aliases when available; static references work without PHP or a parser. Value annotations are opt-in with `:BladeNavToggleShowValues`.

---

## 🧰 Ex Commands & Command Palette Actions

All commands below are registered in the **Command Palette** (`<C-S-p>` or `:CommandPalette`):

* `:BladeNavClearCache` – Clears cached Laravel routes, views, config, env, and translation entries.
* `:BladeNavToggleShowValues` – Toggles inline config/env/translation virtual text annotations.
* `:BladeNavInstallArtisanCommand` – Installs the local component-alias helper command without overwriting existing files; copies it to `app/Console/Commands/BladeNav.php`.
* `:FormatDocument` (or `:ConformFormat`) – Formats active `.php` or `.blade.php` buffer using Pint / PHP-CS-Fixer / blade-formatter.
* `:LanguageManager` – Opens the interactive UI manager to install or uninstall the PHP & Laravel language bundle.

---

## 🐞 Xdebug Debugger Profiles (`<F5>`)

Press `<F5>` (`:DapContinue`) to launch the Debug Adapter Protocol (DAP) launcher:

1. **`🐘 Listen for Xdebug (Vanilla PHP / Laravel Web / Herd)`**: Listens on port `9003` for incoming requests from web servers (Laravel Herd, Nginx, Apache, PHP built-in server).
2. **`📄 Launch Current Script (Vanilla PHP CLI)`**: Executes current `.php` file under PHP CLI with Xdebug enabled.
3. **`🚀 Debug Laravel Artisan Command`**: Prompts for artisan command (e.g., `migrate`, `queue:work`) and executes under Xdebug.
4. **`🌐 Debug Laravel App (artisan serve)`**: Launches `php artisan serve` with Xdebug enabled.

> 🔴 **Blade Breakpoints**: Breakpoints can be toggled inside `.blade.php` files (`<A-b>` or `:DapToggleBreakpoint`), and Xdebug will pause execution during view rendering.

---

## ⚡ JavaScript in Blade Templates (`<script>` & `@script`)

Blade templates frequently incorporate JavaScript blocks for frontend interactions and Livewire scripts:

1. **Syntax Highlighting & Treesitter Injections**:
   - Standard `<script>` and `<script type="module">` tags are automatically injected into `javascript`.
   - `<script lang="ts">` or `<script lang="typescript">` tags are automatically injected into `typescript`.
   - Livewire 3 `@script ... @endscript` blocks are parsed and injected as `javascript`.
2. **Formatting**:
   - `:FormatDocument` (`blade-formatter`) automatically cleans up and indents HTML, Blade directives, and embedded `<script>` blocks.
3. **Autocompletion & Tooling**:
   - `html-lsp` (`vscode-html-language-server`), `tailwindcss`, and local Laravel completion attach to Blade buffers, providing HTML/script completion, component navigation, and Tailwind utility class suggestions.
4. **Tailwind CSS & SCSS Dynamic Scoping**:
   - `tailwindcss` LSP only attaches to a `.blade.php` buffer if the file actually contains at least one Tailwind class, variant, or directive (e.g. `class="flex..."`, `@apply`, `hover:`). Buffers without Tailwind classes remain lean with no unnecessary background LSP overhead.
   - Embedded `<style>` blocks default to standard `css`. Only when explicitly declared via `<style lang="scss">`, `<style type="text/scss">`, or containing SCSS syntax (`$variable:`, `@mixin`, `@include`), does it switch to `scss`.



Blade syntax and indentation are local (`fox.langs.php.blade`), using Neovim’s built-in PHP/HTML syntax. `@script`/`@assets` pairs and `g:blade_custom_directives_pairs` are supported. The `=` operator uses the local Blade indent function even when a Treesitter parser is installed.
