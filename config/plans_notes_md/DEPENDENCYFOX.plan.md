# PLAN — Reducir dependencias externas de FoxVim

Objetivo: clonar e instalar menos plugins y mantener aquí las funciones que usamos. Orden de menor a mayor dificultad estimada para el uso actual de FoxVim, no para copiar todas las funciones de cada proyecto. Es una estimación basada en las specs y consumidores locales; cada sustitución requiere revisar su implementación.

Inventario de partida: **49 plugins externos**, incluido lazy.nvim y las dependencias transitivas. **21 reemplazos completados: 28 externos actuales**, de los cuales **11 siguen pendientes de reemplazo y 17 son Vital-Exceptions**. Inventario vigente: [PLUGINS-LIST.md](PLUGINS-LIST.md).

## Criterio de ejecución

- Un reemplazo por cambio: revisar consumidores y comandos, implementar o reutilizar módulos locales, probar, retirar specs/lockfile y actualizar ambos documentos.
- Mantener APIs utilizadas y datos existentes. Usar Neovim y lua/fox/ antes de añadir código. Las posiciones cercanas pueden ajustarse al revisar cada implementación.
- Mantener Lua como instalación mínima; lenguajes opcionales solo por selección explícita en LanguageManager.
- Los plugins de la tabla Vital-Exceptions se conservan como dependencias externas; no forman parte de los reemplazos pendientes.
- Menos clones no significa cero herramientas: LSPs, formateadores, adaptadores, Git, runtimes y gramáticas siguen siendo necesarios.
- Una copia vendorizada sigue siendo código externo. Preferir implementación propia; conservar licencias y atribuciones al reutilizar código o recursos.

## Plan de implementación, de más fácil a más difícil

| Orden | Plugin externo | Dificultad | Estado | Sustitución del uso actual |
|---|---|---|---|---|
| 1 | `zapling/mason-conform.nvim` | Muy fácil | Completado | Reutilizar LanguageManager y Mason/PATH; retirar la instalación automática del puente. |
| 2 | `s1n7ax/nvim-window-picker` | Fácil | Completado | Selector nativo con etiquetas, filtros de ventanas y cancelación; conservar integración Neo-tree. |
| 3 | `theHamsta/nvim-dap-virtual-text` | Fácil-media | Completado | Extmarks para variables DAP; limpiar al continuar, cerrar y cambiar de sesión. |
| 4 | `leoluz/nvim-dap-go` | Fácil-media | Completado | Registrar Delve y perfiles en fox.langs.go; conservar tests y attach utilizados. |
| 5 | `jay-babu/mason-nvim-dap.nvim` | Fácil-media | Completado | Resolver adaptadores desde los metadatos y rutas Mason locales; verificar cada adaptador. |
| 6 | `doki-theme/doki-theme-vim` | Fácil-media | Completado | Conservar temas seleccionables, recursos y atribuciones; restaurar selección al iniciar. |
| 7 | `ahmedkhalf/project.nvim` | Media | Completado | Historial y raíz locales; migrar datos y consumidores sin perder favoritos ni WSL. |
| 8 | `goolord/alpha-nvim` | Media | Completado | Buffer inicial propio con botones, acciones, geometría y navegación por teclado. |
| 9 | `windwp/nvim-ts-autotag` | Media | Completado | Cerrar/renombrar etiquetas con Treesitter; cubrir JSX, fragmentos y etiquetas vacías. |
| 10 | `Wansmer/symbol-usage.nvim` | Media | Completado | Referencias LSP y extmarks con debounce y protección ante respuestas atrasadas. |
| 11 | `Hoffs/omnisharp-extended-lsp.nvim` | Media | Completado | Traducir respuestas de OmniSharp y abrir fuentes de metadatos; conservar navegación C#. |
| 12 | `nvim-tree/nvim-web-devicons` | Media | Completado | API local compatible; mini.icons conserva el catálogo hasta el siguiente reemplazo. |
| 13 | `nvim-mini/mini.icons` | Media | Completado | Catálogo local, colores, sufijos compuestos, overrides por lenguaje y API devicons. |
| 14 | `brenoprata10/nvim-highlight-colors` | Media | Completado | Colores CSS/Tailwind a extmarks; preservar formatos configurados y rendimiento al editar. |
| 15 | `williamboman/mason-lspconfig.nvim` | Media | Completado | Mapear paquetes a servidores desde metadatos locales; mantener activación y selección mínima. |
| 16 | `Crysthamus/nvim-file-operations` | Media | Completado | Sincronizar buffers con operaciones Neo-tree sin perder cambios sin guardar. |
| 17 | `antosha417/nvim-lsp-file-operations` | Media | Completado | Eventos will/didRename, create y delete; filtrar clientes y aplicar workspace edits de forma segura. |
| 18 | `jwalton512/vim-blade` | Media | Completado | Syntax, detección e indentación locales de Blade; cubrir mezcla HTML/PHP y directivas. |
| 19 | `ricardoramirezr/blade-nav.nvim` | Media | Completado | Resolver vistas, componentes y rutas Laravel con caché local. |
| 20 | `f-person/git-blame.nvim` | Media | Completado | Reutilizar fox.git para blame asíncrono y enlaces; conservar comandos y repositorios anidados. |
| 21 | `nvim-lualine/lualine.nvim` | Media-alta | Completado | Statusline nativa con diseños del picker y actualizaciones Git/LSP sin bloqueos. |
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
| 34 | `MeanderingProgrammer/render-markdown.nvim` | Alta | Pendiente | Renderizado incremental con Treesitter y extmarks; tablas, bloques y modos de edición. |

## Vital-Exceptions

Dependencias que el usuario decidió conservar. Quedan fuera del plan de implementación y no se reescriben al invocar `$dependency-rewriter`. Se mantienen sus números originales para referencia.

| Orden original | Plugin externo | Dificultad estimada original |
|---|---|---|
| 32 | `folke/snacks.nvim` | Alta |
| 33 | `iamcco/markdown-preview.nvim` | Alta |
| 35 | `stevearc/conform.nvim` | Alta |
| 36 | `neovim/nvim-lspconfig` | Alta |
| 37 | `lewis6991/gitsigns.nvim` | Muy alta |
| 38 | `NeogitOrg/neogit` | Muy alta |
| 39 | `rcarriga/nvim-dap-ui` | Muy alta |
| 40 | `nvim-neo-tree/neo-tree.nvim` | Muy alta |
| 41 | `MunifTanjim/nui.nvim` | Muy alta |
| 42 | `nvim-neotest/nvim-nio` | Muy alta |
| 43 | `nvim-lua/plenary.nvim` | Muy alta |
| 44 | `nvim-telescope/telescope.nvim` | Muy alta |
| 45 | `williamboman/mason.nvim` | Muy alta |
| 46 | `folke/lazy.nvim` | Muy alta |
| 47 | `saghen/blink.cmp` | Extrema |
| 48 | `mfussenegger/nvim-dap` | Extrema |
| 49 | `nvim-treesitter/nvim-treesitter` | Extrema |

## Primer ítem completado: mason-conform.nvim

- Eliminadas su spec y su entrada de lazy-lock.json; una instalación nueva ya no lo clona.
- Reutilizada la implementación local existente: cada lenguaje declara sus formateadores y paquetes; fox.core.installer los presenta e instala mediante :LanguageManager.
- Conform depende directamente de Mason para encontrar ejecutables instalados en PATH, sin otro puente ni instalaciones al abrir archivos.
- Conservados overrides por lenguaje, condiciones de formato, formato al guardar y comandos :FormatDocument, :ConformFormat y :ConformInfo.
- Pruebas nuevas: agregación de configuración, dependencia directa y presencia de formateadores gestionados en sus bundles. El mínimo Lua ya tiene cobertura en installer_spec.lua.
- No se borran carpetas de instalaciones anteriores. El gestor podrá mostrar la dependencia retirada como no utilizada; no se necesita para arrancar.

## Segundo ítem completado: nvim-window-picker

- Implementación propia en `lua/fox/core/window_picker.lua`, sin dependencias adicionales. `lua/window-picker.lua` conserva el nombre de módulo que requiere Neo-tree.
- Selección síncrona por letras en la barra superior de cada ventana, sin cambiar el foco. Si solo hay un destino válido, se elige automáticamente.
- Excluye la ventana actual, otras pestañas, flotantes, ventanas no enfocables, árboles, notificaciones, terminales y quickfix.
- Restaura las barras originales al seleccionar, cancelar, interrumpir o cerrar un destino. Usa etiquetas de varias letras cuando hay muchos destinos.
- Retiradas la spec externa y su entrada del lockfile; actualizados el inventario, README y documentación. Las carpetas de instalaciones anteriores no se borran.
- Ocho pruebas con ventanas reales cubren compatibilidad, selección, filtros, restauración, cancelación, interrupción, cierre y etiquetas múltiples.

## Tercer ítem completado: nvim-dap-virtual-text

- Implementación propia en `lua/fox/dap/virtual_text.lua`, conectada directamente a los listeners de nvim-dap. Reutiliza los scopes y variables ya recibidos; no añade peticiones al adaptador.
- Mantiene referencias y definiciones del ámbito detenido mediante consultas `locals` de Treesitter, valores comentados al final de línea desde la columna 80, límite de 60 caracteres y resaltado de cambios entre paradas.
- Limpia al continuar, avanzar, desconectar, salir, terminar o cambiar de sesión; ignora respuestas de sesiones inactivas y respuestas tardías mientras se ejecuta.
- Conserva los cuatro comandos `DapVirtualText*` y los registra en Command Palette; muestra detalles de excepciones y paradas por data breakpoint.
- Retiradas la dependencia y su entrada del lockfile; diez pruebas con parser Lua y extmarks reales cubren renderizado, ámbitos, Unicode, ciclo de vida y controles.
- Igual que antes, las anotaciones de variables requieren un parser y una consulta `locals` del lenguaje; no se instalan parsers adicionales automáticamente.

## Cuarto ítem completado: nvim-dap-go

- Adaptador Delve y siete perfiles originales definidos en `lua/fox/langs/go/init.lua`: archivo, argumentos, argumentos y flags, paquete, attach, test por archivo y test por paquete.
- Mantiene el puerto dinámico, host/puerto explícitos y tiempo de inicialización; usa el ejecutable nativo de Mason si existe y conserva el modo attached en Windows.
- Los prompts esperan la respuesta del input modal, reutilizan el parser de argumentos de nvim-dap y cancelan el lanzamiento al pulsar Escape. Attach reutiliza su selector de procesos.
- Delve sigue siendo un paquete opcional del bundle Go; no se añaden instalaciones automáticas. No se recrean APIs de tests bajo cursor que FoxVim no consumía.
- Retiradas la dependencia y su entrada del lockfile; actualizadas las guías y la prueba de integración. Cinco pruebas cubren perfiles, adaptador, rutas, aislamiento y prompts.
- Comprobación real con Go y Delve: compilar un programa temporal, parar en un breakpoint, leer `value = 41`, continuar y salir correctamente.

## Quinto ítem completado: mason-nvim-dap.nvim

- Python, PHP y C# registran sus adaptadores en sus módulos de lenguaje; Firefox se registra en el módulo compartido de navegadores. Go, Bash, C/C++ y JS ya tenían registro local.
- Usa ejecutables nativos y scripts Node de los paquetes Mason; evita wrappers `.cmd` al lanzar los adaptadores. Conserva el fallback a PATH y los perfiles existentes.
- Mason es una dependencia directa de DAP para exponer las herramientas instaladas. LanguageManager mantiene la selección explícita; no se instalan adaptadores al arrancar ni al abrir archivos.
- Retiradas la spec y su entrada del lockfile; corregidas las instrucciones que sugerían descargar adaptadores al reiniciar.
- Cinco pruebas verifican rutas Windows/Unix, entrypoints Node, Codelldb, fallback y paquetes instalados después del registro. Comprobación real: Python, PHP, CoreCLR y Bash respondieron correctamente a `initialize` del protocolo DAP.

## Sexto ítem completado: doki-theme-vim

- El catálogo de FoxThemePicker y el tema guardado (`nagatoro-fox`) ya se implementaban completamente en `config/colors/`, sin usar código de ejecución del plugin Doki.
- Sustituida su spec externa por `fox_theme_startup`, una spec local eager en `lua/plugins/ui/themes.lua`. Conserva intacta la restauración y sincronización Ryoku/Omarchy.
- Retirada la entrada del lockfile. No se copian fuentes ni recursos del repositorio externo; se conservan las atribuciones de las paletas locales existentes.
- Dos pruebas verifican el arranque local y la carga de todas las paletas estáticas del selector sin Doki en runtimepath. Los nombres adicionales exclusivos del catálogo upstream dejan de distribuirse; no formaban parte del selector FOX ni del tema guardado.

## Séptimo ítem completado: project.nvim

- `fox.projects.history` adopta el archivo `project_nvim/project_history` existente, sin cambiar su formato ni borrar proyectos inaccesibles. Las lecturas no hacen stat de las rutas de proyectos ni arrancan WSL.
- Guardado inmediato mediante archivo temporal y rename atómico; ante errores de lectura, escritura o reemplazo conserva el archivo original y los consumidores informan del error.
- Picker, Telescope y explorador usan la API local. Se mantienen los favoritos, WSL, renombrado, borrado, comandos y teclas existentes.
- `:ProjectRoot` busca el marcador más cercano y usa el root del LSP como fallback; solo cambia cwd cuando se invoca. La extensión local conserva `:Telescope projects` y la selección de proyectos de Environments.
- Retiradas ambas declaraciones externas y el lockfile. Siete pruebas del historial y dos del comando pasaron; una comprobación de integración abrió el picker real desde la extensión local de Telescope.

## Reemplazo 8: goolord/alpha-nvim

Dashboard propio en fox.ui.dashboard con buffer scratch, botones originales, navegación, centrado responsive, comandos Alpha/AlphaRedraw y evento AlphaReady. Conserva el filetype alpha para los consumidores FOX, WSL, pines y restauración al cerrar el último buffer. Cinco pruebas con buffers reales cubren render, navegación, acciones, protección de cambios y restauración de opciones de ventana. Corregida la paridad visual: botones de 50 columnas, texto alineado a la izquierda y atajos a la derecha; cursor dentro de la opción, sin resaltar la fila completa. Comparación directa con Alpha: nueve filas con emoji idénticas a 40, 80 y 120 columnas. No requiere clonar Alpha.

## Reemplazo 9: windwp/nvim-ts-autotag

Implementación propia en fox.editor.autotag: cierre con Treesitter, respeto de etiquetas vacías/autocerradas, JSX con miembros y fragmentos, y renombrado de ambos extremos mediante extmarks. No adivina si falta parser. Cinco casos con parsers HTML/TSX reales y comprobación de inserción real verifican cierre, cursor, texto dentro de la etiqueta, renombrado y entradas incompletas. TSX se compiló solo en /tmp para verificarlo; no se instaló ningún bundle opcional.

## Reemplazo 10: Wansmer/symbol-usage.nvim

Contador propio en fox.lsp.symbol_usage con documentSymbol/references, virt_lines, debounce, cancelación, límite de cuatro peticiones simultáneas y rechazo de respuestas antiguas o clientes desconectados. Mantiene los formatos bubbles/plain/labels del picker. Seis pruebas con respuestas controladas y comprobación real con gopls: función Foo con dos usos mostró 2 references. Retirada la dependencia externa y el lockfile.

## Reemplazo 11: Hoffs/omnisharp-extended-lsp.nvim

Navegación propia en fox.langs.csharp.navigation. Traduce los cuatro endpoints utilizados y carga metadata/sourcegeneratedfile de forma asíncrona en buffers readonly aislados por cliente; conserva el nombre del servidor al navegar desde esos buffers y no sobrescribe ediciones. Mantiene saltos únicos, Telescope y quickfix, posiciones UTF-16 y rechazo de respuestas tardías. Ocho pruebas con respuestas de protocolo controladas cubren estas rutas; no había OmniSharp/.NET instalado para verificar un servidor C# real.

## Reemplazo 12: nvim-tree/nvim-web-devicons

API de compatibilidad propia en fox.ui.devicons y lua/nvim-web-devicons.lua. Conserva resolución por archivo/extensión/filetype, sufijos compuestos, overrides por lenguaje, colores, defaults y catálogo. Los consumidores dependen ahora del catálogo mini.icons (su sustitución es el siguiente ítem), sin clonar devicons ni usar su mock. Cinco pruebas de API, las 36 pruebas de Query y arranque real con Neo-tree/Telescope/bufferline/lualine verifican iconos y ausencia de la spec externa. Suite completa: 853 aprobadas y 2 fallos preexistentes en ProjectRoot y aislamiento del tema Ryoku, reproducidos con el código anterior.

## Reemplazo 13: nvim-mini/mini.icons

Resolución propia en fox.ui.icons con los metadatos originales de mini.icons en icon_data.lua (atribución y licencia MIT en licenses/mini.icons.txt). Conserva el catálogo completo, sufijos compuestos, filetypes, rutas Windows, overrides por lenguaje y colores. Corrección de paridad visual: 1.281 consultas comparadas con el plugin instalado sin diferencias; nueve pruebas unitarias de iconos/devicons y dos integraciones NestJS aprobadas.

## Reemplazo 14: brenoprata10/nvim-highlight-colors

Previews nativos con extmarks, CSS hex/rgb/hsl, nombres y variables; Tailwind opt-in reutiliza colorify. Debounce y render limitado a ventanas visibles y líneas acotadas. Conserva HighlightColors y añade acción de paleta. Tres pruebas con buffers reales cubren Unicode, edición, formatos y variables; sin dependencias externas.

## Reemplazo 15: williamboman/mason-lspconfig.nvim

Mapeo desde metadatos de lenguajes y genéricos existentes, sin instalaciones automáticas. Conserva LspInstall con selección cancelable, versiones y LspUninstall; activación mediante vim.lsp.config/enable. 17 pruebas de tooling/installer aprobadas e integración real LuaLS adjunto sin mason-lspconfig.

## Reemplazo 16: Crysthamus/nvim-file-operations

Sincronización nativa integrada en Neo-tree: renombrado conserva buffer/undo; borrado conserva ediciones en fox-recovered:// para guardar con saveas. No auto-guarda ni intercepta globalmente workspace edits. Seis pruebas unitarias y una integración real de eventos y archivo movido aprobadas. El plugin anterior no tenía consumidores de sus APIs públicas.

## Reemplazo 17: antosha417/nvim-lsp-file-operations

Bridge nativo para will/did Rename/Create/Delete, filtros por workspace/scheme/glob/tipo, timeout total de 1.5s y workspace edits con encoding del cliente. Rechaza versiones obsoletas, cambios concurrentes y operaciones de recursos recursivas; nunca guarda ediciones automáticamente. Cuatro pruebas unitarias y una integración stdio con servidor fixture verifican edición y notificación reales; sin servidor opcional instalado.

## Reemplazo 18: jwalton512/vim-blade

Sintaxis e indentación propias en fox.langs.php.blade y puentes syntax/indent; reutiliza sintaxis PHP/HTML de Neovim, conserva comentarios, ecos, verbatim y pares personalizados script/assets. Detección Blade propiedad del módulo PHP; Treesitter respeta el indentexpr local. Seis pruebas unitarias y una integración real gg=G aprobadas. Sin copiar código upstream.

## Reemplazo 19: ricardoramirezr/blade-nav.nvim

Índice propio por proyecto Artisan para vistas/componentes/Livewire/rutas/config/env/traducciones/Inertia, gf y fuente Blink cancelable. Caché con TTL, invalidación al guardar y rechazo de procesos antiguos; consultas Artisan asíncronas para rutas y aliases. Conserva los tres comandos de paleta y helper local de instalación exclusiva. Nueve pruebas unitarias y una integración real de navegación/completado aprobadas. PHP y parser PHP no disponibles: no se ejecutó el helper contra Laravel real.

## Reemplazo 20: f-person/git-blame.nvim

Blame asíncrono propio en fox.git.inline_blame y parser compartido en fox.git.blame; reutiliza el constructor Git con soporte WSL. Conserva comandos, fechas relativas, cambios sin guardar, repositorios anidados, URL por forge y copia de SHA. Cancela procesos y rechaza resultados antiguos; ignora archivos excluidos por Git. Once pruebas unitarias relacionadas y cuatro integraciones con Git real aprobadas.

## Validación del lote Media (2026-10-25)

- Ocho reemplazos pendientes completados; 29 externos y 68 specs locales activas, verificados desde el registro real de Lazy. Los directorios de specs locales son únicos mediante fox.core.lazyspec.
- Suite completa: 892 aprobadas y dos fallos en autotag TSX y aislamiento del selector de temas. Ambos casos también fallan al ejecutar el commit inicial 255bb17 en un worktree separado (857 aprobadas y dos fallos); no se atribuyen a este lote.
- Once integraciones del lote aprobadas juntas: registro de specs, iconos NestJS, buffers Neo-tree, transporte LSP stdio, indentación Blade, navegación/completado Laravel y cuatro casos Git reales. LuaLS inicializó y respondió documentSymbol sin mason-lspconfig.
- 824 archivos Lua sin errores de sintaxis; StyLua y Luacheck aprobados para los 46 archivos Lua modificados, sin advertencias. Los artefactos binarios reconstruidos por las pruebas se restauraron y el worktree de comparación se retiró.
- No hay PHP ni parser PHP disponibles: las respuestas Artisan se validaron con procesos controlados; el helper PHP no se ejecutó contra Laravel real. No se instalaron bundles opcionales ni se eliminaron directorios de plugins instalados.

## Reemplazo 21: nvim-lualine/lualine.nvim

- Renderer propio en `fox.ui.statusline` con statusline global nativa, seis diseños del picker, separadores, colores por modo/colorscheme, truncamiento nativo, diagnósticos y símbolos de archivos modificados/readonly. Conserva Editor/Query, entorno, Python, LSP y títulos de terminal/tarea.
- Git asíncrono con timeout, caché, cancelación y rechazo de respuestas antiguas; reutiliza `fox.git.cmd` para Windows/WSL. Ramas normales, sin commits, HEAD separado y worktrees; contadores de GitSigns con fallback a diff asíncrono del archivo guardado. Refresca al guardar, cambiar de directorio/foco y recibir eventos de editor/LSP/GitSigns.
- Se conserva `:FoxStatuslineTheme`, su acción de paleta y `.foxnvim/statusline.json`; cancelar no escribe y un fallo de guardado informa sin aplicar el diseño. Consumidores de Environments migrados; retirada la spec externa y el lockfile. No se copia código upstream ni se eliminan directorios instalados.
- 17 pruebas unitarias de statusline aprobadas y tres integraciones reales: arranque/persistencia, Git/diff/worktree y terminal/LSP stdio con fixture. Integración de registro de specs aprobada; Lazy verifica 28 externos y 69 locales. No se ejecutó Windows/WSL en esta máquina Linux.
- Suite completa: 902 aprobadas y dos fallos ajenos al cambio (autotag TSX y aislamiento del selector de temas), reproducidos también desde el commit inicial 538703b. Syntax y StyLua/Luacheck sin errores para los archivos del cambio.

## Siguiente ítem

`akinsho/bufferline.nvim`: continuar con el alcance indicado en la tabla.
