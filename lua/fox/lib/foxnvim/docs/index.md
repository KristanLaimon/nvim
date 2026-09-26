# 🦊 foxnvimscript Wiki & Documentation

Bienvenido a la documentación interactiva de **foxnvimscript** (`foxnvim.*`).

**foxnvimscript** es una suite de utilidades diseñada para facilitar la creación de scripts de consola, automatización de tareas, scripts de build y herramientas CLI en Lua utilizando Neovim.

---

## 🎹 Atajos de Teclado Principales

- **`Ctrl + ,`** (`<C-,>`): Ejecuta y guarda inmediatamente el script `.lua` actual dentro de Neovim o abre Launch Profiles.
- **`Ctrl + Shift + ,`** (`<C-S-,>`): Abre esta ventana flotante de **Documentación Wiki**.

---

## 📦 Módulos Disponibles en `foxnvim.*`

1. **`import(...)`**: Carga rápida de módulos y archivos JSON, YAML o TOML.
2. **`foxnvim.terminal`** (`$ "command"`): Ejecución de comandos de terminal cross-platform.
3. **`foxnvim.json`**: Parser, encoder y operaciones de archivo JSON.
4. **`foxnvim.yaml`**: Parser y encoder YAML nativo en Lua.
5. **`foxnvim.toml`**: Parser y encoder TOML nativo en Lua.
6. **`foxnvim.cli`**: Parseo de argumentos `--help` y menús numéricos interactivos.
7. **`foxnvim.fs`**: Helper para lectura, escritura y manipulación de archivos.
8. **`foxnvim.fetch`**: API tipo `fetch` para peticiones HTTP/HTTPS en Lua puro (sin curl).
9. **`foxnvim.test`**: Librería de testing tipo Vitest / Bun:test (`describe`, `test`, `expect`).
10. **`foxnvim.foxnvimtranspiler`**: Transpilador automático de `.foxnvim` a scripts equivalentes `.sh` (Bash) y `.ps1` (PowerShell) con CLI nativos.
11. **`foxnvim.async`** (`concurrent`, `parallel`): Concurrencia, paralelismo multinúcleo en OS threads y primitivas async/await.

---

## ⚡ Ejemplo Rápido

```lua
local $ = require("fox.lib.foxnvim.terminal")
local json = import("foxnvim.json")
local config = import("config.yaml")

print("=== Running Build Script ===")
local res = $("git status")
print(res.stdout)
```
