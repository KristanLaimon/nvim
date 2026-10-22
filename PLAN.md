# PLAN — Reducir dependencias externas de FoxVim

Objetivo: clonar e instalar menos plugins y mantener aquí las funciones que usamos. Orden de menor a mayor dificultad estimada para el uso actual de FoxVim, no para copiar todas las funciones de cada proyecto. Es una estimación basada en las specs y consumidores locales; cada sustitución requiere revisar su implementación.

Inventario de partida: **49 plugins externos**, incluido lazy.nvim y las dependencias transitivas. Primer reemplazo completado: **48 restantes**. Inventario vigente: [PLUGINS-LIST.md](PLUGINS-LIST.md).

## Criterio de ejecución

- Un reemplazo por cambio: revisar consumidores y comandos, implementar o reutilizar módulos locales, probar, retirar specs/lockfile y actualizar ambos documentos.
- Mantener APIs utilizadas y datos existentes. Usar Neovim y lua/fox/ antes de añadir código. Las posiciones cercanas pueden ajustarse al revisar cada implementación.
- Mantener Lua como instalación mínima; lenguajes opcionales solo por selección explícita en LanguageManager.
- Nui, Nio y Plenary tienen consumidores compartidos. Su posición indica dificultad; retirarlos exige migrar antes esos consumidores.
- Menos clones no significa cero herramientas: LSPs, formateadores, adaptadores, Git, runtimes y gramáticas siguen siendo necesarios.
- Una copia vendorizada sigue siendo código externo. Preferir implementación propia; conservar licencias y atribuciones al reutilizar código o recursos.

## Lista completa, de más fácil a más difícil

| Orden | Plugin externo | Dificultad | Estado | Sustitución del uso actual |
|---|---|---|---|---|
| 1 | `zapling/mason-conform.nvim` | Muy fácil | Completado | Reutilizar LanguageManager y Mason/PATH; retirar la instalación automática del puente. |
| 2 | `s1n7ax/nvim-window-picker` | Fácil | Pendiente | Selector nativo con etiquetas, filtros de ventanas y cancelación; conservar integración Neo-tree. |
| 3 | `theHamsta/nvim-dap-virtual-text` | Fácil-media | Pendiente | Extmarks para variables DAP; limpiar al continuar, cerrar y cambiar de sesión. |
| 4 | `leoluz/nvim-dap-go` | Fácil-media | Pendiente | Registrar Delve y perfiles en fox.langs.go; conservar tests y attach utilizados. |
| 5 | `jay-babu/mason-nvim-dap.nvim` | Fácil-media | Pendiente | Resolver adaptadores desde los metadatos y rutas Mason locales; verificar cada adaptador. |
| 6 | `doki-theme/doki-theme-vim` | Fácil-media | Pendiente | Conservar temas seleccionables, recursos y atribuciones; restaurar selección al iniciar. |
| 7 | `ahmedkhalf/project.nvim` | Media | Pendiente | Historial y raíz locales; migrar datos y consumidores sin perder favoritos ni WSL. |
| 8 | `goolord/alpha-nvim` | Media | Pendiente | Buffer inicial propio con botones, acciones, geometría y navegación por teclado. |
| 9 | `windwp/nvim-ts-autotag` | Media | Pendiente | Cerrar/renombrar etiquetas con Treesitter; cubrir JSX, fragmentos y etiquetas vacías. |
| 10 | `Wansmer/symbol-usage.nvim` | Media | Pendiente | Referencias LSP y extmarks con debounce y protección ante respuestas atrasadas. |
| 11 | `Hoffs/omnisharp-extended-lsp.nvim` | Media | Pendiente | Traducir respuestas de OmniSharp y abrir fuentes de metadatos; conservar navegación C#. |
| 12 | `nvim-tree/nvim-web-devicons` | Media | Pendiente | Cubrir API mediante iconos locales y retirar specs consumidoras; hoy mini.icons aporta un mock. |
| 13 | `nvim-mini/mini.icons` | Media | Pendiente | Catálogo local, colores, sufijos compuestos, overrides por lenguaje y API devicons. |
| 14 | `brenoprata10/nvim-highlight-colors` | Media | Pendiente | Colores CSS/Tailwind a extmarks; preservar formatos configurados y rendimiento al editar. |
| 15 | `williamboman/mason-lspconfig.nvim` | Media | Pendiente | Mapear paquetes a servidores desde metadatos locales; mantener activación y selección mínima. |
| 16 | `Crysthamus/nvim-file-operations` | Media | Pendiente | Sincronizar buffers con operaciones Neo-tree sin perder cambios sin guardar. |
| 17 | `antosha417/nvim-lsp-file-operations` | Media | Pendiente | Eventos will/didRename, create y delete; filtrar clientes y aplicar workspace edits de forma segura. |
| 18 | `jwalton512/vim-blade` | Media | Pendiente | Syntax, detección e indentación locales de Blade; cubrir mezcla HTML/PHP y directivas. |
| 19 | `ricardoramirezr/blade-nav.nvim` | Media | Pendiente | Resolver vistas, componentes y rutas Laravel con caché local. |
| 20 | `f-person/git-blame.nvim` | Media | Pendiente | Reutilizar fox.git para blame asíncrono y enlaces; conservar comandos y repositorios anidados. |
| 21 | `nvim-lualine/lualine.nvim` | Media-alta | Pendiente | Statusline nativa con diseños del picker y actualizaciones Git/LSP sin bloqueos. |
| 22 | `akinsho/bufferline.nvim` | Media-alta | Pendiente | Tabline nativa con fijados, diagnósticos, cierre y desbordamiento. |
| 23 | `rafamadriz/friendly-snippets` | Media-alta | Pendiente | Snippets locales de los lenguajes usados; conservar cobertura y licencias de datos migrados. |
| 24 | `rcarriga/nvim-notify` | Media-alta | Pendiente | Cola de ventanas, expiración, historial y protección del foco. |
| 25 | `windwp/nvim-autopairs` | Media-alta | Pendiente | Reglas de inserción/borrado, undo, completion y exclusiones de sintaxis. |
| 26 | `vuki656/package-info.nvim` | Media-alta | Pendiente | Versiones y acciones por gestor con caché, errores de red y edición segura del manifiesto. |
| 27 | `m00qek/baleia.nvim` | Media-alta | Pendiente | Parser ANSI incremental a highlights; escapes fragmentados y buffers DAP. |
| 28 | `vyfor/cord.nvim` | Alta | Pendiente | IPC Discord con reconexión y presencia; validar Windows, Linux y entornos remotos. |
| 29 | `b0o/schemastore.nvim` | Alta | Pendiente | Catálogo local y selección de schemas; definir cómo mantener actualizados sus datos. |
| 30 | `nvim-telescope/telescope-file-browser.nvim` | Alta | Pendiente | Migrar consumidores al explorador propio conservando navegación y operaciones. |
| 31 | `sindrets/diffview.nvim` | Alta | Pendiente | Diff e historial con fox.git; conservar integración de Neogit. |
| 32 | `folke/snacks.nvim` | Alta | Pendiente | Inventariar APIs consumidas y sustituirlas con módulos FOX; cubrir solo funciones utilizadas. |
| 33 | `iamcco/markdown-preview.nvim` | Alta | Pendiente | Servidor y vista web locales con recarga, scroll y renderizado seguro; quitar build externo. |
| 34 | `MeanderingProgrammer/render-markdown.nvim` | Alta | Pendiente | Renderizado incremental con Treesitter y extmarks; tablas, bloques y modos de edición. |
| 35 | `stevearc/conform.nvim` | Alta | Pendiente | Procesos asíncronos, condiciones, rangos, errores y guardado sin perder cambios. |
| 36 | `neovim/nvim-lspconfig` | Alta | Pendiente | Usar vim.lsp con datos por lenguaje y migrar utilidades/root_dir consumidos. |
| 37 | `lewis6991/gitsigns.nvim` | Muy alta | Pendiente | Hunks incrementales, signos y stage/reset parcial sin dañar el índice de Git. |
| 38 | `NeogitOrg/neogit` | Muy alta | Pendiente | Completar funciones equivalentes en Git Center antes de retirar comandos e integraciones. |
| 39 | `rcarriga/nvim-dap-ui` | Muy alta | Pendiente | Paneles scopes, stacks, watches, REPL y consola con layouts y sesiones. |
| 40 | `nvim-neo-tree/neo-tree.nvim` | Muy alta | Pendiente | Árbol, watchers y operaciones seguras; migrar extensiones FOX y estado Git/ventanas. |
| 41 | `MunifTanjim/nui.nvim` | Muy alta | Pendiente | Migrar APIs de UI de todos sus consumidores; retirar después de Neo-tree/package-info. |
| 42 | `nvim-neotest/nvim-nio` | Muy alta | Pendiente | Migrar async y cancelación de dap-ui; eliminar tras su consumidor si deja de necesitarse. |
| 43 | `nvim-lua/plenary.nvim` | Muy alta | Pendiente | Migrar jobs, async y paths de todos los consumidores, incluidos módulos FOX. |
| 44 | `nvim-telescope/telescope.nvim` | Muy alta | Pendiente | Buscador/framework propios; migrar pickers FOX, extensiones y acciones. |
| 45 | `williamboman/mason.nvim` | Muy alta | Pendiente | Descargas, versiones, extracción y binarios multiplataforma; conservar selección explícita. |
| 46 | `folke/lazy.nvim` | Muy alta | Pendiente | Carga diferida, dependencias, bootstrap, lockfile y actualizaciones; migrar specs primero. |
| 47 | `saghen/blink.cmp` | Extrema | Pendiente | Motor de completion, ranking, LSP/snippets y fuentes FOX; cancelación y edición rápida. |
| 48 | `mfussenegger/nvim-dap` | Extrema | Pendiente | Cliente DAP con transportes, sesiones, breakpoints y REPL compatible con adaptadores. |
| 49 | `nvim-treesitter/nvim-treesitter` | Extrema | Pendiente | API Treesitter nativa, queries y gestión/compilación de parsers; gramáticas siguen externas. |

## Primer ítem completado: mason-conform.nvim

- Eliminadas su spec y su entrada de lazy-lock.json; una instalación nueva ya no lo clona.
- Reutilizada la implementación local existente: cada lenguaje declara sus formateadores y paquetes; fox.core.installer los presenta e instala mediante :LanguageManager.
- Conform depende directamente de Mason para encontrar ejecutables instalados en PATH, sin otro puente ni instalaciones al abrir archivos.
- Conservados overrides por lenguaje, condiciones de formato, formato al guardar y comandos :FormatDocument, :ConformFormat y :ConformInfo.
- Pruebas nuevas: agregación de configuración, dependencia directa y presencia de formateadores gestionados en sus bundles. El mínimo Lua ya tiene cobertura en installer_spec.lua.
- No se borran carpetas de instalaciones anteriores. El gestor podrá mostrar la dependencia retirada como no utilizada; no se necesita para arrancar.

## Siguiente ítem

`s1n7ax/nvim-window-picker`: sustituir el selector usado por Neo-tree con APIs nativas y probar filtros, cancelación y selección. Los demás reemplazos permanecen pendientes.
