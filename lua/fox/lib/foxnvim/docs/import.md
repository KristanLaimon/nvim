# 📥 Función Global import()

`foxnvimscript` incluye la función `import()` que reemplaza o extiende a `require()` detectando automáticamente la extensión del archivo.

## Ejemplos de Uso

```lua
-- Importar módulos nativos de foxnvim
local $ = import("foxnvim.terminal")
local json = import("foxnvim.json")

-- Importar datos directamente desde archivos
local pkg = import("package.json")
local config = import("settings.yaml")
local cargo = import("Cargo.toml")
```
