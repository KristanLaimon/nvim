# 🪐 Astro Development Guide

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

Astro is an independent **Web Frameworks (Astro)** bundle in `:LanguageManager`. It installs the Astro language server, Biome, and the Astro Treesitter parser without pulling in the Vanilla Web or Web UI bundles.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server** | `astro` | Completion, diagnostics, navigation, and embedded TypeScript support for `.astro` files |
| **Formatter** | Biome; optional Prettier | Project-installed `prettier` with `prettier-plugin-astro` takes priority; otherwise Biome |
| **Treesitter** | `astro` | Syntax highlighting and structure |
| **Requires** | Node.js | Required by the Astro language server |

Use `:FormatDocument` to format the active file. Biome works without project dependencies or a project config. FoxVim supplies a default config enabling experimental full Astro support, including the HTML template. This requires Biome 2.3 or newer; update Biome through Mason if needed.

If the project has its own Biome config, FoxVim uses it instead. Enable complete Astro formatting there with:

```json
{
  "html": {
    "experimentalFullSupportEnabled": true,
    "formatter": { "enabled": true }
  }
}
```

To prefer Prettier, install both formatting dependencies in your Astro project (or use your package manager's equivalent):

```sh
npm install --save-dev prettier prettier-plugin-astro
```

FoxVim loads the Astro plugin explicitly, even without a Prettier config. An optional `.prettierrc.astro.json` overrides formatting for Astro files. Restart Neovim after installing the dependencies.

The language server resolves the TypeScript SDK at startup, checking the project and its parent workspaces first, then the SDK bundled with Mason's Astro language server. It only uses SDKs containing `typescript.js` or `tsserverlibrary.js`.
