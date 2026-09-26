---
name: foxnvimscript
description: Write, run, test and transpile `.foxnvim` automation scripts (Lua-based build/CLI scripting suite shipped with Neovim config at lua/foxnvim/). Use whenever a task needs a build script, task runner, CLI tool, HTTP call, JSON/YAML/TOML file handling, or testing and requires explicit `foxnvim.*` modules (`require("foxnvim.<module>")`), with zero reliance on global imports.
---

# foxnvimscript

Lua automation suite living in the Neovim configuration (`lua/foxnvim/`). Scripts are plain Lua saved in `*.foxnvim` files and run anywhere Neovim is installed — zero external runtime dependencies (no Node, Python, or curl required). Scripts can also be transpiled to native `.sh` (Bash) and `.ps1` (PowerShell) for CI/CD environments and servers.

Use it for: build scripts, task runners, CLI tools, HTTP/HTTPS API integrations, JSON/YAML/TOML file manipulation, and unit test suites.

> [!IMPORTANT]
> Global imports on `_G` (such as global `import()`, `console`, `fetch`) have been removed. All modules must be explicitly imported using `require("foxnvim.<module>")` or `require("foxnvim")`.

## Run & Execute

```bash
# Execute a script headlessly from the command line
nvim --headless -l build.foxnvim
```

Inside Neovim:
- `<C-,>` runs/saves the active `.foxnvim` script (or opens Launch Profiles).
- `<C-S-,>` opens the floating wiki documentation.
- `.foxnvim` files automatically register with filetype `foxnvim` and Lua syntax highlighting.

---

## Requires & Module Import Syntax

Scripts must import specific submodules directly using `require("foxnvim.<module>")`:

```lua
local fs = require("foxnvim.fs")
local json = require("foxnvim.json")
local terminal = require("foxnvim.terminal")
local fetch = require("foxnvim.fetch")
local console = require("foxnvim.console")
```

Alternatively, import the master module to access all submodules from a single table:

```lua
local fox = require("foxnvim")
local fs = fox.fs
local json = fox.json
```

---

## Available Modules & API Reference

### 1. `foxnvim.terminal` — Command Execution
Cross-platform synchronous terminal execution (`cmd.exe /C` on Windows, `bash -c` on Unix).

```lua
local terminal = require("foxnvim.terminal")

-- Execute command string or table array of tokens
local res = terminal.exec("git status") -- { code, ok, stdout, stderr, output }
assert(res.ok, "git status failed with exit code: " .. res.code)

-- Calling module directly as alias `$`
local $ = require("foxnvim.terminal")
local build_res = $("bun run build")

-- Helpers
local cwd = terminal.cwd()         -- string: current working directory
local is_win = terminal.is_windows -- boolean: true if host OS is Windows
terminal.echo("Message")           -- prints to output
```

### 2. `foxnvim.fs` — File System Operations
High-performance file system and path operations.

- `fs.exists(path)` -> `boolean`: Checks if file, directory, or glob pattern exists.
- `fs.read(path)` -> `string`: Reads entire file text. Throws error if file cannot be opened.
- `fs.write(path, content)` -> `boolean`: Overwrites or creates file.
- `fs.mkdir(path)` -> `boolean`: Recursively creates directory tree (`mkdir -p`).
- `fs.list(dir_path)` -> `table`: Returns array of file and folder paths contained within directory.

```lua
local fs = require("foxnvim.fs")

if not fs.exists("dist") then
    fs.mkdir("dist")
end
fs.write("dist/version.txt", "1.0.0")
local files = fs.list("src")
```

### 3. Data Parsers — `foxnvim.json`, `foxnvim.yaml`, `foxnvim.toml`
Pure Lua and C-accelerated configuration file parsers and serializers sharing a consistent API.

- `.decode(str)` -> `table|any`: Parses formatted text string into Lua table.
- `.encode(obj)` -> `string`: Serializes Lua table into formatted text.
- `.load(filepath)` -> `table|any`: Reads file from disk and parses contents.
- `.save(filepath, obj)` -> `boolean`: Encodes Lua table and writes directly to disk.

```lua
local json = require("foxnvim.json")
local yaml = require("foxnvim.yaml")
local toml = require("foxnvim.toml")

-- JSON (C-accelerated via vim.json)
local pkg = json.load("package.json")
pkg.version = "1.1.0"
json.save("package.json", pkg)

-- YAML
local docker = yaml.load("docker-compose.yml")

-- TOML
local cargo = toml.load("Cargo.toml")
```

### 4. `foxnvim.fetch` — HTTP / HTTPS Client
Web-standard HTTP client supporting JSON auto-encoding/decoding, URL query formatting, and case-insensitive headers.

```lua
local fetch = require("foxnvim.fetch")

-- Standard GET
local res = fetch.get("https://api.github.com/zen")
print("Status:", res.status, "OK:", res.ok)
print("Body text:", res:text())

-- Automatic JSON parsing
local api_res = fetch.get("https://api.github.com/repos/neovim/neovim")
local repo, err = api_res:json()
if repo then
    print("Stars:", repo.stargazers_count)
end

-- POST / PUT / PATCH / DELETE / HEAD
local post_res = fetch.post("https://httpbin.org/post", {
    name = "foxnvimscript",
    tags = { "lua", "nvim" }
}, {
    headers = { ["Authorization"] = "Bearer token123" },
    query = { verbose = "true" },
    timeout = 10000 -- ms
})
```

`FetchResponse` fields and methods:
- `res.status` (`number`), `res.statusText` (`string`), `res.ok` (`boolean`)
- `res.headers` (case-insensitive table)
- `res.body` (`string`), `res.url` (`string`)
- `res:text()` -> `string`: Returns raw body text
- `res:json()` -> `table|nil, err`: Safely parses body as JSON table

### 5. `foxnvim.console` — Formatted Logging
Formatted console output, structured object inspection, and cycle-safe JSON pretty-printing. Available globally as `console`.

```lua
local console = require("foxnvim.console")

console.log("Building target:", { env = "prod", minified = true })
console.info("Server started on port", 8080)
console.warn("Deprecation warning:", "feature X")
console.error("Build failed:", "Missing file")
console.debug("State:", state)

-- Pretty print & stringify
console.dir(tbl)                       -- Prints formatted JSON representation of table/object
local json_str = console.json(tbl, "  ") -- Serializes object to pretty JSON string

-- Direct callable alias
console("Quick log message")           -- Equivalent to console.log(...)
```

### 6. `foxnvim.cli` — Argument Parsing & Interactive Menus
Command-line argument parser, help text generator, and interactive selection UI helper.

```lua
local cli = require("foxnvim.cli")

-- Argument parsing (--flag, --key=value, -v, positional)
local args = cli.parse_args(arg, {
    options = { env = "Environment", verbose = "Enable verbose logging" }
})
-- args.flags.env -> "production"
-- args.flags.verbose -> true
-- args.positional[1] -> "build"

-- Help doc generator
local help_str = cli.help({
    name = "build-tool",
    description = "Automated project builder",
    options = { env = "Target environment", clean = "Clean dist directory first" }
})

-- Interactive menu (uses vim.ui.select in Neovim UI, terminal prompts in standalone CLI)
cli.menu("Select Target", { "Production", "Staging", "Development" }, function(choice, idx)
    print("Selected:", choice, "at index:", idx)
end)
```

### 7. `foxnvim.test` — Testing Framework
Vitest/Bun:test inspired test suite runner with BDD syntax and chainable matchers.

```lua
local t = require("foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local beforeEach, afterEach = t.beforeEach, t.afterEach

describe("Calculator Test Suite", function()
    beforeEach(function()
        -- setup state
    end)

    it("should perform addition", function()
        expect(2 + 2).toBe(4)
        expect({ name = "nvim" }).toEqual({ name = "nvim" })
        expect("foxnvimscript").toContain("nvim")
        expect(10).toBeGreaterThan(5)
        expect(function() error("fail") end).toThrow()
    end)

    it("should handle negations", function()
        expect(5).not_.toBe(10)
        expect(nil).toBeNil()
    end)
end)

-- Execute test runner
t.run()
```

Matchers available:
- `toBe(val)`, `toEqual(val)` (deep equality check)
- `toBeTruthy()`, `toBeFalsy()`
- `toBeNil()`, `toBeNull()`, `toBeUndefined()`, `toBeDefined()`
- `toContain(item)`, `toHaveLength(len)`
- `toBeGreaterThan(n)`, `toBeGreaterThanOrEqual(n)`, `toBeLessThan(n)`, `toBeLessThanOrEqual(n)`
- `toThrow(err_msg)`
- Negate matchers with `.not_`, `.isNot`, or `["not"]` (e.g., `expect(x).not_.toBe(y)`).

### 8. `foxnvim.foxnvimtranspiler` — Script Transpilation
Transpiles `.foxnvim` scripts into standalone `.sh` (Bash) and `.ps1` (PowerShell) scripts that run on machines without Neovim.

```lua
local transpiler = require("foxnvim.foxnvimtranspiler")

transpiler.export_sh("build.foxnvim")   -- Generates build.sh
transpiler.export_ps1("build.foxnvim")  -- Generates build.ps1
transpiler.export_both("build.foxnvim") -- Generates build.sh and build.ps1
local sh_code = transpiler.to_sh(lua_str)
local ps1_code = transpiler.to_ps1(lua_str)
```

Neovim buffer commands:
- `:FoxExport [sh|ps1|both] [out]`
- `:FoxExportSh`
- `:FoxExportPs1`

Transpiler supports: standard functions, `print`, `assert`, `error`, `fs.*`, `fetch.get/json`, `json.*`, `yaml.load`, `$ "cmd"`, `for`/`while` loops, and imperative control flow. Avoid complex metatables or UI callbacks in scripts intended for transpilation.

### 9. `foxnvim.wiki` — Interactive Wiki Documentation
Opens an interactive floating Markdown documentation viewer inside Neovim.

```lua
local wiki = require("foxnvim.wiki")
wiki.open("index.md") -- Opens floating documentation UI with single-key page switching (1-6)
```

---

## Project Configuration & Launch Profiles

Per-project configuration files live in `.foxnvim/` at the root of a project:
- `.foxnvim/tasks.json` — Custom tasks and commands.
- `.foxnvim/launch.json` — Launch profiles for running/debugging scripts.
- `.foxnvim/breakpoints.json` — Saved breakpoints.

To configure a launch profile for `foxnvimscript`:
```json
{
  "name": "Run foxnvimscript",
  "type": "foxnvimscript",
  "request": "launch",
  "entry_point": "scripts/build.foxnvim"
}
```

---

## Code Example & Style Guide

Always use explicit `require("foxnvim.<module>")` at the top of the file, check result objects, and assert on error states.

```lua
-- build.foxnvim
local $ = require("foxnvim.terminal")
local fs = require("foxnvim.fs")
local json = require("foxnvim.json")
local console = require("foxnvim.console")

console.info("Starting build process...")

if not fs.exists("dist") then
    fs.mkdir("dist")
end

local pkg = json.load("package.json")
console.log("Building package:", pkg.name, "v" .. pkg.version)

local res = $("bun run build")
assert(res.ok, "Build execution failed: " .. res.output)

fs.write("dist/BUILD_VERSION", pkg.version)
console.info("Build completed successfully!")
```
