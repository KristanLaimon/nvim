# 🐳 Docker Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

FoxVim provides editing, validation, autocompletion, and formatting for **Dockerfiles** and **Docker Compose** files.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Dockerfile LSP** | `dockerls` | Dockerfile linting, diagnostics, and validation |
| **Docker Compose LSP** | `docker_compose_language_service` | Docker compose syntax validation, service keys, and completions |
| **Formatters (Conform)** | `dockerfmt`, `prettier` | Dockerfile and Docker Compose formatting |
| **Treesitter Parsers** | `dockerfile`, `yaml` | Syntax trees for Dockerfiles and Compose YAML |
| **Autocompletion** | `blink.cmp` | Keyword, service, and instruction completion |

---

## 📄 Filetype Recognition & Associations

FoxVim automatically recognizes standard Compose filenames (`docker-compose.yml`, `compose.yaml`, `docker-compose.*.yml`, `compose.*.yaml`) as `yaml.docker-compose`.

For non-standard Docker or Docker Compose filenames (e.g., `services.dev.yml`, `docker.txt`), use `:SetBufferLanguage` from the Command Palette (`<C-S-p>`) to persistently associate the file.

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:SetBufferLanguage` – Persistently set the language / filetype for current file.
* `:FormatDocument` – Format Dockerfile or Docker Compose YAML.
* `:LanguageManager` – Install or uninstall Docker bundle.
