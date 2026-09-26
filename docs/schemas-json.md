# Local JSON Schemas Management Guide

[← Back to Wiki Index](index.md)

This guide explains how offline, 100% local JSON schema validation and autocompletion are configured in Neovim using `jsonls`, `schemastore.nvim`, and local JSON schema files stored in `schemas/json/`.

---

## 📁 Directory Structure & Key Files

- **Local JSON Schemas Folder:** `schemas/json/` ([`stdpath("config") .. "/schemas/json/"`](../schemas/json))
- **LSP Configuration File:** [`lua/plugins/lsp/lsp.lua`](../lua/plugins/lsp/lsp.lua)

---

## 📋 Currently Installed Local JSON Schemas

| Tool / Schema | Local File Path | Applied File Patterns (`fileMatch`) | Configuration Type |
|---|---|---|---|
| **TypeScript** | `schemas/json/tsconfig.json` | `tsconfig*.json` | Standard SchemaStore override (`replace`) |
| **npm package.json** | `schemas/json/package.json` | `package.json` | Standard SchemaStore override (`replace`) |
| **Prettier** | `schemas/json/prettierrc.json` | `.prettierrc`, `.prettierrc.json` | Standard SchemaStore override (`replace`) |
| **ESLint** | `eslintrc.json` | `.eslintrc`, `.eslintrc.json` | Standard SchemaStore override (`replace`) |
| **JSConfig** | `schemas/json/jsconfig.json` | `jsconfig.json` | Standard SchemaStore override (`replace`) |
| **Babel** | `schemas/json/babelrc.json` | `.babelrc`, `.babelrc.json`, `babel.config.json` | Standard SchemaStore override (`replace`) |
| **Turborepo** | `schemas/json/turbo.json` | `turbo.json` | Standard SchemaStore override (`replace`) |
| **Biome** | `schemas/json/biome.json` | `biome.json`, `biome.jsonc` | Custom schema entry (`extra`) |
| **FoxVim Snippets** | `snippets/snippets.schema.json` | `snippets/*.json`, `snippets/**/*.json` | Custom schema entry (`extra`) |

---

## 🧠 Understanding `select`, `replace`, and `extra` Properties

In [`lua/plugins/lsp/lsp.lua`](../lua/plugins/lsp/lsp.lua), `require("schemastore").json.schemas({...})` uses three main options to filter and override schemas:

### 1. `select` (Whitelisting Schemas)
- **Purpose**: Restricts Neovim to load **only** the schema names explicitly listed in this array, ignoring all other internet schemas in SchemaStore.
- **Rule**: Every schema you want Neovim to use (whether standard or custom) **must** be listed in `select`.

### 2. `replace` (Overriding Known SchemaStore Schemas)
- **Purpose**: Used for schemas that exist in the official SchemaStore catalog (e.g., `tsconfig.json`, `package.json`, `.eslintrc`).
- **How it works**: Maps the official SchemaStore schema key to your local file URI created via `get_schema_uri("json", "filename.json")`.
- **Example**:
  ```lua
  replace = {
      ["tsconfig.json"] = get_schema_uri("json", "tsconfig.json"),
      ["package.json"] = get_schema_uri("json", "package.json"),
  }
  ```

### 3. `extra` (Adding Custom or Non-Catalog Schemas)
- **Purpose**: Used for custom schemas or schemas that are **NOT** present in the official SchemaStore catalog (e.g., `biome.json`, `my-app-config.json`).
- **How it works**: Allows defining custom objects containing:
  - `name`: Identifier string (must match the name added to `select`).
  - `description`: Short summary of the schema.
  - `fileMatch`: Array of filename globs/patterns that trigger this schema.
  - `url`: The local file URI using `get_schema_uri("json", "filename.json")`.
- **Example**:
  ```lua
  extra = {
      {
          name = "my-custom-schema.json",
          description = "Custom app configuration schema",
          fileMatch = { "my-app.json", "*.custom.json" },
          url = get_schema_uri("json", "my-custom-schema.json"),
      },
  }
  ```

---

## 📝 TODO Checklist: How to Add a New JSON Schema

Follow this step-by-step checklist whenever you want to add a new JSON schema to Neovim.

- [ ] **Step 1: Download or save the JSON schema file**
  Save the schema `.json` file inside `schemas/json/`.  
  *Example file path:* `C:\Users\Fox\AppData\Local\nvim\schemas\json\my-schema.json`

- [ ] **Step 2: Open [`lua/plugins/lsp/lsp.lua`](../lua/plugins/lsp/lsp.lua)**
  Locate `opts.servers.jsonls.settings`.

- [ ] **Step 3: Add schema name to `select` array**
  ```lua
  select = {
      "tsconfig.json",
      "package.json",
      -- ... existing schemas ...
      "my-schema.json", -- <-- Added here
  }
  ```

- [ ] **Step 4: Configure `replace` OR `extra`**

  - **If the schema exists in standard SchemaStore**, add a mapping in `replace`:
    ```lua
    replace = {
        -- ... existing replacements ...
        ["my-schema.json"] = get_schema_uri("json", "my-schema.json"),
    }
    ```

  - **If the schema is custom or NOT in SchemaStore**, add an entry in `extra`:
    ```lua
    extra = {
        -- ... existing extra schemas ...
        {
            name = "my-schema.json",
            description = "My custom schema description",
            fileMatch = { "my-config.json", "*.myconfig.json" },
            url = get_schema_uri("json", "my-schema.json"),
        },
    }
    ```

- [ ] **Step 5: Restart Neovim or run `:ReloadConfig`**

- [ ] **Step 6: Verify LSP Validation**
  1. Open a target matching file (e.g. `my-config.json`).
  2. Run `:LspInfo` to confirm `jsonls` is attached.
  3. Intentionally introduce an invalid key to check for diagnostic error underlinings.
