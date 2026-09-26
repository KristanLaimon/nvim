# 🧬 How to Create / Update / Delete / Register a Lua Type Schema

[← Back to Wiki Index](index.md)

This is the by-hand companion to [Type Injector](type-injector.md): everything the picker (`:FoxTypes`) does through menus, done directly on the filesystem. Use this when you're adding a new SDK's types (a game engine, an app's plugin API, an embedded Lua host) and don't want to go through the NPM install flow (that only exists for TypeScript/JavaScript — see [Managing TypeScript Type Schemas](how-to-manage-typescript-type-schemas.md) for that language's by-hand equivalent).

A **schema** is just a directory of `.lua` stub files under `schemas-langs/lua/<name>/`. There is no registry to update — `scan_available_schemas()` reads the filesystem, so a directory that exists *is* an available schema.

---

## 🏗️ Create a new schema

### Step 1: Pick a name and a location

```
schemas-langs/lua/<schema_name>/
```

Two roots are searched (see `M.get_schema_roots` in `lua/plugins/fox/type_injector.lua`):

1. `stdpath("data")/schemas-langs/lua/<schema_name>/` — where NPM installs land; fine for personal, throwaway, or machine-local schemas.
2. `stdpath("config")/schemas-langs/lua/<schema_name>/` (this repo's `schemas-langs/lua/`) — versioned with the rest of FoxVim; use this for anything you want to keep and share across machines.

### Step 2: Write the stub file(s)

Any `.lua` file in the directory is loaded by `lua_ls` once the schema is active — there's no required filename, though a single `<schema_name>_types.lua` (e.g. `koreader_types.lua`) is the convention here. Start every file with:

```lua
---@meta
```

`---@meta` tells `lua_ls` this file only declares types — it's never executed, so it's safe to overwrite globals with fake tables like `Foo = Foo or {}`.

Two annotation styles cover almost everything:

**A) A real bare global** — the SDK sets a variable with no `local`, so it exists in every file without a `require`:

```lua
---@class LuaSettings
---@field readSetting fun(self: LuaSettings, key: string, default?: any): any

---@type LuaSettings
G_reader_settings = G_reader_settings or {}
```

**B) A `require()`-returned module** — most SDK APIs are *not* bare globals; code does `local Foo = require("foo")`. A hand-written stub schema can't make `require("foo")` itself resolve to a real file (that needs the actual annotated source on `workspace.library`, not a stub folder) — so stub schemas instead give a same-named global purely so ad-hoc snippets referencing the bare name still get completion. Say so in a comment; don't let it look like `require()` is covered when it isn't.

> ⚠️ **Verify against the real source before writing a stub** — don't guess field/method names. Grep the SDK's own source for what's actually global (e.g. `grep -rnE "^[A-Za-z_][A-Za-z0-9_]*\s*=\s*" <sdk_src> | grep -v "^\s*local"`) and for the real call sites (`grep -rn 'require("foo")'`) so the stub matches how the SDK is actually used, not an invented convenience namespace.

### Step 3: Version it

Add a `package.json` next to the stub file(s) so the picker shows a version and you can keep multiple versions side by side later (e.g. `schemas-langs/lua/koreader/` today, `schemas-langs/lua/koreader-v2027.01/` later):

```json
{
  "name": "fox-schema-<schema_name>",
  "private": true,
  "version": "<sdk version, e.g. output of `git describe --tags`>",
  "description": "What this stub covers and where it came from.",
  "source": "<upstream repo/docs URL>"
}
```

`M.get_schema_version()` reads `.version` from this file (also checking `node_modules/@types/<name>/package.json`, for schemas installed via NPM) and prefixes it with `v` in the picker label. No `package.json` just means no version shown — the schema still works.

---

## ✅ Register (activate) a schema for a project

A schema existing on disk doesn't mean any project uses it — that's a separate per-project decision.

**Through the picker (recommended):** open the target project in Neovim, run `:FoxTypes` (or `:TypeInjector`) from a `.lua` buffer, and toggle the schema on with `<Enter>`/`<Tab>`/`<Space>`. This writes `.foxnvim/types.json` and pushes the new `Lua.workspace.library` to the running `lua_ls` immediately — no restart needed.

**By hand:** create/edit `.foxnvim/types.json` at the project root:

```json
{
  "lua": ["<schema_name>"]
}
```

Multiple schemas can be active at once — list them all. This file is per-project state, not per-schema — commit it, it's the project's own decision about which type sets it wants.

If `lua_ls` is already attached, either restart it (`:LspRestart`) or re-run `:FoxTypes` and toggle the schema once (off, on) so `apply_lsp_settings()` fires and pushes the updated library list live.

---

## ✏️ Update a schema

There's no "edit" command — just edit the `.lua` file(s) in `schemas-langs/lua/<schema_name>/` directly, and bump `version` in its `package.json` if the change tracks a new SDK release. Any project with the schema active picks up the change the next time `lua_ls` reloads that file (usually automatic; `:LspRestart` if not).

---

## 🗑️ Delete a schema

**Through the picker:** select the schema, `<C-d>` — this asks for confirmation, deletes the schema directory (`vim.fn.delete(schema_dir, "rf")`), and deactivates it in every project's `.foxnvim/types.json` you touch afterward (deactivation is per-project, so other projects' `types.json` entries become dangling references — harmless, `scan_available_schemas()` just won't list the name anymore).

**By hand:** delete `schemas-langs/lua/<schema_name>/` (from whichever root it's actually in — check both with `M.get_schema_roots("lua")` if unsure), and remove the name from `.foxnvim/types.json` in any project that had it active.

---

## 🔍 Quick reference

| Action | Picker | By hand |
| :--- | :--- | :--- |
| Create | `<C-n>` (TS/JS only, via NPM) | `mkdir schemas-langs/lua/<name>` + write `.lua` stub(s) + optional `package.json` |
| Register for a project | `<Enter>`/`<Tab>`/`<Space>` | Add name to `.foxnvim/types.json` → `"lua": [...]` |
| Update | — | Edit the `.lua` file(s) in place |
| Deregister | `<Enter>`/`<Tab>`/`<Space>` (toggle off) | Remove name from `.foxnvim/types.json` |
| Delete | `<C-d>` | `rm -rf schemas-langs/lua/<name>` + remove from any project's `types.json` |

See [Type Injector](type-injector.md) for how the wiring works end to end (LSP notification, TS reference-file generation, etc.).
