# Lua development

FoxVim uses `lua_ls`, StyLua and the Lua Treesitter parser for ordinary `.lua` files.
The minimal fresh installation remains Lua only.

## Libraries and completion

Use standard `require` calls for module paths, members, signatures and documentation:

```lua
local fs = require("fox.lib.foxnvim.fs")
local json = require("fox.lib.foxnvim.json")
local fox = require("fox.lib.foxnvim")

local exists = fs.exists("data.json")
local data = json.decode('{"enabled":true}')
fox.console.log(data)
```

LuaLS searches `?.lua`, `?/init.lua`, `lua/?.lua` and `lua/?/init.lua` in the
project, and loads FoxVim libraries, installed plugin Lua directories and LuaRocks
trees through the type injector. Optional type schemas remain project selections.
For custom module layouts, add `runtime.path` entries in the project's `.luarc.json`.
LuaLS infers members from modules that return a table; C modules need type definitions.
See [LuaLS settings](https://luals.github.io/wiki/settings/#runtimepath).

The libraries require Neovim. Run the current Lua file with `<C-,>` or a launch
profile using runtime `lua`; `<C-S-,>` opens their wiki. The runner loads the
FoxVim globals. External plain Lua interpreters do not provide Neovim's APIs.
The old script-specific filetype, runtimes and shell transpilation are removed;
rename old `.foxnvim` scripts to `.lua` and set launch profiles to runtime `lua`.
The former script adapter ran a process without implementing DAP; Lua debugging
requires a real Lua debug adapter.

## Commands

- `:FormatDocument`: format the current Lua file with StyLua.
- `:TypeInjector`: select project type definitions.
- `:LanguageManager`: manage the Lua toolchain.
