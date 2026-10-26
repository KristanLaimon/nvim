# 🟨 TypeScript & JavaScript Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

FoxVim provides a high-performance **TypeScript / JavaScript** environment supporting Node.js, Bun, React (JSX/TSX), Vue, Svelte, and Astro.

---

## Package versions and dependency actions

Open a saved `package.json`, then search **Packages:** in the Command Palette.
Opening the file never starts a package manager. These actions are local to FoxVim:

| Command | Action |
|---|---|
| `:PackageInfoShow` | Query available versions and display inline annotations |
| `:PackageInfoShowForce` | Refresh, bypassing the one-hour session cache |
| `:PackageInfoHide` / `:PackageInfoToggle` | Hide or toggle the annotations |
| `:PackageInfoUpdate` | Confirm an update of the dependency on the current line |
| `:PackageInfoDelete` | Confirm removal of that dependency |
| `:PackageInfoInstall` | Choose production/development and enter one package name |
| `:PackageInfoChangeVersion` | Choose a published stable version for that dependency |

The nearest `packageManager` field or lockfile chooses npm, pnpm, Yarn or Bun;
Bun is the fallback. Actions run in the manifest's directory, including monorepo
packages, and preserve development dependency placement. Registry reads use pnpm
for pnpm projects and npm otherwise, matching the previous plugin's tooling
requirements. Project `.npmrc` settings apply. Only four reads run concurrently;
results are cached per package directory and stale responses are ignored.

Save the manifest before changing dependencies. If it changes while a prompt is
open, the action stops. If you edit during a running command, FoxVim keeps your
buffer edits and asks you to review the manifest written by the manager. The
manager owns installation and lockfile updates. Failures and timeouts are reported;
changes a failed manager command already wrote are not automatically undone.

Put each dependency on its own line to select it. Production and development
sections are supported. Local/workspace references are skipped for registry queries;
aliases and catalog references can display available registry versions, but update
and version-change actions require editing their source instead of replacing the
reference. Up-to-date versions and prereleases are hidden by default. Settings
live in `fox.langs.typescript.package_info`; the implementation is in its
`packages` submodule. `require("package-info")` remains a compatibility entrypoint.

## NestJS file icons

NestJS files use distinct role icons in the explorer, tabs, and file pickers:
controllers use red sliders, modules purple cubes, services orange gears, and
`.spec.ts` / `.spec.js` tests green flasks. Guards, interceptors, pipes, filters,
middleware, gateways, decorators, DTOs, entities, and resolvers each have their own
role icon, including JavaScript equivalents.
`nest-cli.json` uses the red NestJS logo. Mappings live in
`lua/fox/langs/typescript/init.lua` under `M.icons` and apply by filename suffix.

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `vtsls`, `eslint`, `biome` | TypeScript/JavaScript language server with auto-imports and inlay hints |
| **Formatters (Conform)** | `prettierd`, `prettier`, `biome` | Priority chain: `prettierd` → `prettier` → `biome` (`stop_after_first = true`) |
| **Treesitter Parsers** | `typescript`, `javascript`, `tsx`, `jsx` | Complete syntax parsing for TS, JS, and React |
| **Autocompletion** | `blink.cmp` | LSP completions, snippets, path autocompletion, and Tailwind CSS color previews |
| **Debug Adapter (DAP)** | `js-debug-adapter`, Bun adapter | `pwa-node` (Node.js), `pwa-chrome` (Chrome), `pwa-msedge` (Edge), and Bun DAP |
| **Type Injector** | `plugins.fox.tools.type_injector` | Automatic type acquisition and project `@types` helper |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:TypeInjector` – Open modular type injector modal to manage TypeScript definitions and project typings.
* `:TailwindOrganize` – Re-order Tailwind CSS classes in JSX/TSX/HTML according to standard class sorting guidelines.
* `:TailwindOrganizerToggle` – Toggle auto-organizing Tailwind CSS classes on save.
* `:FormatDocument` – Format active file using Prettier/Prettierd/Biome.
* `:LanguageManager` – Install the shared TypeScript components from the **Web UI (Svelte, Angular, React)** bundle.

---

## 🐞 Debugger Profiles (`<F5>`)

1. **`pwa-node`**: Attach to or launch Node.js scripts with `js-debug-adapter`.
2. **`pwa-chrome` / `pwa-msedge`**: Launch browser or attach to web dev servers (Vite, Next.js, Nuxt, React).
3. **Bun Debugger**: Direct debugging for Bun scripts and test suites.

---

## ⚡ JavaScript in HTML Files (`<script>`)

`vtsls` dynamically scopes activation on HTML documents:
- **Active on Inline Scripts**: Only activates on `.html` files when an inline `<script>` tag with actual content inside is present.
- **Ignored on External Scripts**: Files with only `<script src="..."></script>` (or non-JS scripts like `type="importmap"` / `type="application/json"`) do not attach `vtsls`, preventing unnecessary background processes.
- **Dynamic Attachment**: As soon as inline script content is written into an HTML file, `vtsls` attaches automatically.

