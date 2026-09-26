# 📄 Formatos de Datos: JSON, YAML, TOML

`foxnvim` proporciona parsers y serializadores unificados para los formatos de configuración y datos más populares.

## JSON (`foxnvim.json`)

```lua
local json = require("fox.lib.foxnvim.json")

-- Parsear y serializar
local data = json.decode('{"name": "fox", "version": 1}')
local str = json.encode(data)

-- Leer y guardar archivos
local config = json.load("config.json")
json.save("out.json", { status = "ok" })
```

## YAML (`foxnvim.yaml`)

```lua
local yaml = require("fox.lib.foxnvim.yaml")

local data = yaml.load("settings.yaml")
yaml.save("output.yaml", { app = "nvim", mode = "dark" })
```

## TOML (`foxnvim.toml`)

```lua
local toml = require("fox.lib.foxnvim.toml")

local data = toml.load("Cargo.toml")
print(data.package and data.package.name)
```
