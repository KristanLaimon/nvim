# PLAN — Reducir dependencias externas de FoxVim

Objetivo: clonar e instalar menos plugins y mantener aquí las funciones que usamos. La tabla `Pendientes` ordena el trabajo de menor a mayor dificultad y riesgo para el uso actual de FoxVim, hasta los reemplazos súper difíciles. No busca copiar todas las funciones de cada proyecto. La viabilidad depende también de los consumidores transitivos y del mantenimiento que asumiría FOX.

Inventario de partida: **49 plugins externos**, incluido lazy.nvim y las dependencias transitivas. **27 reemplazos completados y 22 externos pendientes de evaluación/implementación**. Por petición explícita del usuario, las 17 antiguas excepciones vuelven a la misma cola que los 5 pendientes anteriores; ya no existe una tabla de exclusiones. Inventario vigente: [PLUGINS-LIST.md](PLUGINS-LIST.md).

Reevaluación: **2026-10-26**, sobre las specs y consumidores actuales, las implementaciones instaladas relevantes y el historial hasta `d9c13c9` (Baleia completado en `2720075`). Esta revisión solo cambia el plan: no inicia reemplazos, no modifica la skill, no retira dependencias ni altera `lazy-lock.json`, que ya tenía cambios ajenos.

## Criterio de ejecución

- Un reemplazo por cambio: revisar consumidores y comandos, implementar o reutilizar módulos locales, probar, retirar specs/lockfile y actualizar ambos documentos.
- Mantener APIs utilizadas y datos existentes. Usar Neovim y lua/fox/ antes de añadir código. Las posiciones cercanas pueden ajustarse al revisar cada implementación.
- Mantener Lua como instalación mínima; lenguajes opcionales solo por selección explícita en LanguageManager.
- `Pendientes` es la única cola de implementación. La autorización de esta revisión es únicamente documental; las futuras sustituciones se ejecutarán cuando el usuario las solicite. Los requisitos previos de cada fila prevalecen sobre su posición.
- Menos clones no significa cero herramientas: LSPs, formateadores, adaptadores, Git, runtimes y gramáticas siguen siendo necesarios.
- Una copia vendorizada sigue siendo código externo. Preferir implementación propia; conservar licencias y atribuciones al reutilizar código o recursos.

## Reemplazos completados

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
| 22 | `akinsho/bufferline.nvim` | Media-alta | Completado | Tabline nativa con fijados, diagnósticos, cierre y desbordamiento. |
| 23 | `rafamadriz/friendly-snippets` | Media-alta | Completado | Snippets locales de los lenguajes usados; conservar cobertura y licencias de datos migrados. |
| 24 | `rcarriga/nvim-notify` | Media-alta | Completado | Cola de ventanas, expiración, historial y protección del foco. |
| 25 | `windwp/nvim-autopairs` | Media-alta | Completado | Reglas de inserción/borrado, undo, completion y exclusiones de sintaxis. |
| 26 | `vuki656/package-info.nvim` | Media-alta | Completado | Versiones y acciones por gestor con caché, errores de red y edición segura del manifiesto. |
| 27 | `m00qek/baleia.nvim` | Media-alta | Completado | Parser ANSI incremental a highlights; escapes fragmentados y buffers DAP. |

## Pendientes

Los números siguientes son una nueva secuencia de trabajo, independiente de los 27 reemplazos históricos. **Todas las filas están pendientes y ninguna implementación está iniciada por esta revisión.** La dificultad mide el trabajo de conservar lo utilizado, no la popularidad o tamaño del plugin. Susceptibilidad alta = alcance delimitable y reutilización local clara; media = viable con integración considerable; baja = gran superficie o mantenimiento continuo. No equivale a una garantía de paridad.

| Orden | Plugin externo | Dificultad reevaluada | Susceptibilidad | Alcance, motivo y condición para retirarlo |
|---|---|---|---|---|
| 1 | `nvim-telescope/telescope-file-browser.nvim` | Media | Alta | La spec carga `file_browser`, pero no se encontraron llamadas locales a esa extensión; los exploradores Desktop/WSL y el selector de carpetas ya son FOX sobre Telescope. Verificar la entrada pública `:Telescope file_browser` y sus operaciones antes de migrarla al explorador local. Mantener Telescope y Plenary. Puede requerir principalmente consolidación, no otro explorador. |
| 2 | `b0o/schemastore.nvim` | Media-alta | Alta | Se usan `json.schemas(select/replace/extra)` y `yaml.schemas()`: JSON está seleccionado, YAML usa el catálogo completo. Implementar selección propia y datos atribuidos con actualización manual verificable; conservar asociaciones YAML y prioridad de schemas locales. Menos complejidad de ejecución que la estimación anterior, pero responsabilidad permanente sobre datos. |
| 3 | `folke/snacks.nvim` | Media-alta | Media | Solo declarado desde Neo-tree en el código FOX; el Neo-tree instalado sí consume `snacks.image` en previews. Reutilizar `fox.media.kitty`/ImageViewer donde haya paridad, revisar opciones heredadas y probar preview/cierre/terminales sin Kitty. No basta con borrar la declaración por no encontrar `require` directo. |
| 4 | `neovim/nvim-lspconfig` | Difícil | Alta | Ya se usa `vim.lsp.config/enable`; falta suplir defaults de cada servidor usado (cmd, filetypes, raíces, settings), `lspconfig.util` en C# y accesos heredados en TypeScript/web. Ponerlos en sus módulos de lenguaje y conservar genéricos en el agregador. No reescribir el cliente LSP nativo. |
| 5 | `stevearc/conform.nvim` | Difícil | Alta | Reutilizar `formatters_by_ft` y `conform_formatters` por lenguaje. Aún faltan los defaults que Conform aporta: argumentos, stdin/archivos temporales, cwd, disponibilidad y errores. Preservar cadenas, `stop_after_first`, condiciones por proyecto, timeout al guardar, formato async, fallback LSP, cursor y undo; la ejecución puede modificar código del usuario. |
| 6 | `vyfor/cord.nvim` | Difícil | Media | Presencia/idle, tema Minecraft, repositorio, tiempo, terminal y comandos de toggle/reload. Cord usa además un servidor ejecutable: reemplazar solo su cliente Lua conservaría la dependencia real. Probar framing IPC, named pipes Windows/sockets Unix, reconexión, varias instancias y Discord ausente; WSL/remoto requiere verificar dónde vive Discord. |
| 7 | `MeanderingProgrammer/render-markdown.nvim` | Difícil | Media | Solo Markdown, pero con headings, bloques, listas, checkboxes, citas, callouts y tablas redondeadas. Usar Treesitter/extmarks y conservar conceal, toggle, wiki, posición del cursor, Unicode, tablas alineadas y rendimiento incremental. Mantener parsers y queries mientras se sustituye el renderizador. |
| 8 | `lewis6991/gitsigns.nvim` | Difícil | Media | Configuración directa acotada a signos, archivos untracked, seguimiento y navegación de hunks; revisar también comandos de usuario y paleta. Reutilizar Git FOX y diff nativo, distinguir índice/disco/buffer, ediciones sin guardar y respuestas tardías. Comprobar hunks al inicio/fin, renombres, repositorios anidados y watchers deshabilitados en móvil. |
| 9 | `sindrets/diffview.nvim` | Difícil | Media | FOX ya dispone de diff e historial, pero Neogit declara integración activa. Cubrir revisiones, índice, archivos borrados/binarios, navegación, cierre y restauración de ventanas; migrar la integración de Neogit en este reemplazo o mantener la dependencia hasta resolverla. No confundir abrir dos buffers en diff con paridad de historial. |
| 10 | `iamcco/markdown-preview.nvim` | Difícil | Media | `fox.markdown.browser` ya maneja apertura multiplataforma, comandos globales y buffers Mermaid, pero sigue llamando RPC/Vimscript upstream. Falta servidor local, actualización en vivo y renderizado web. Conservar Markdown/Mermaid, recursos relativos, scroll y ciclo start/stop; validar escape de contenido, acceso local y rutas. Las bibliotecas web reutilizadas necesitan licencias y siguen siendo dependencias externas aunque no sean plugins. |
| 11 | `rcarriga/nvim-dap-ui` | Muy difícil | Media | Paneles scopes/stacks/breakpoints/watches, REPL/consola, evaluación, layouts y listeners usados por DAP/keymaps FOX. Reutilizar floats/docks y ANSI propios; mantener expansión/edición de variables, foco, tamaños y rechazo de respuestas de sesiones antiguas. Conservar el motor nvim-dap. |
| 12 | `nvim-neotest/nvim-nio` | Muy difícil aislado; baja tras 11 | Alta tras 11 | El DAP UI instalado lo requiere en su cliente, variables, ventanas y consola; no se encontró consumo FOX directo. Después de sustituir DAP UI, auditar consumidores restantes y retirar la dependencia si desaparecen. No construir un framework de coroutines solo para eliminar un clon. |
| 13 | `NeogitOrg/neogit` | Muy difícil | Baja | Git Center cubre el flujo diario, pero Neogit añade rebase, stash, cherry-pick e historial. Inventariar popups/acciones usados y extender las pantallas FOX existentes sin perder conflictos, abort/continue, credenciales ni protección de cambios. No retirarlo solo porque Git Center permite stage/commit/push. Resolver sus integraciones con Diffview/Telescope. |
| 14 | `nvim-neo-tree/neo-tree.nvim` | Muy difícil | Media | Gran integración FOX: ancho persistente, movers, ocultos, wrap, Git, eventos LSP, buffers, selector de ventanas, búsquedas y apertura del sistema. Árbol incremental con cancelación, watchers y operaciones seguras en Windows/WSL/móvil. Migrar consumidores de módulos internos y eventos antes de retirar Neo-tree. |
| 15 | `MunifTanjim/nui.nvim` | Muy difícil aislado; baja tras 14 | Alta tras 14 | Neo-tree usa tree/line/text/split/popup/input y utilidades; una fachada pequeña no lo sustituye mientras el árbol siga externo. Tras 14, comprobar que no quedan consumidores y retirar Nui aprovechando las bibliotecas UI FOX, sin recrear toda su API. |
| 16 | `nvim-telescope/telescope.nvim` | Muy difícil | Media | Es infraestructura de la paleta, tareas, launch profiles, workspaces, environments, búsqueda, NuGet, snippets, docs, temas, navegación C# y Query. Crear solo las primitivas compartidas que esos consumidores necesitan: filtrado, acciones, previews, selección y cancelación. Migrar cada consumidor y extensión, incluidas integraciones Git; mantener responsive la búsqueda asíncrona y los contextos WSL/proyecto. |
| 17 | `nvim-lua/plenary.nvim` | Muy difícil aislado; baja tras consumidores | Alta al final de 13–16 | Telescope y Neo-tree instalados consumen módulos Plenary; hay además declaraciones en Neogit/Git Center/workspaces/environments y fallback `plenary.scandir` en Telescope FOX. Auditar también Diffview y herramientas/tests. Sustituir usos FOX por helpers existentes/`vim.uv`/`vim.system`; retirar solo cuando ningún consumidor activo lo requiera. No reimplementar Plenary entero. |
| 18 | `nvim-treesitter/nvim-treesitter` | Súper difícil | Baja | Neovim ya aporta el motor, pero este plugin suministra parsers, instalación/compilación, queries e indentación. Installer consume sus APIs/config; autotag, folding, variables DAP y Markdown dependen de la cobertura resultante. Mantener ABI, queries/injections e indentación por lenguaje, actualizaciones y plataformas; no declarar sustitución completa por usar `vim.treesitter.start`. Gramáticas y sus licencias siguen siendo externas. |
| 19 | `williamboman/mason.nvim` | Súper difícil | Baja | LanguageManager ya tiene UI/metadatos, pero usa registro, paquetes, instalación y rutas Mason; formateo y DAP dependen de sus ejecutables/PATH. Falta resolver descargas, versiones, dependencias, wrappers Windows, fallos parciales, actualización/desinstalación y estado persistente. Mantener herramientas instaladas y mínimo Lua; no delegar todo a instalaciones manuales como supuesto reemplazo equivalente. |
| 20 | `saghen/blink.cmp` | Súper difícil | Baja | Integrar LSP, buffer/path, command line, snippets nativos y proveedores FOX (EditorConfig, Laravel, launch). Conservar capabilities, resolución/documentación, ranking, cancelación, snippets/tabstops, aceptación/undo y comportamiento móvil. Eliminar el binario fuzzy no elimina el resto del motor; requiere pruebas de inserción reales y de rendimiento. |
| 21 | `mfussenegger/nvim-dap` | Súper difícil | Baja | Implementar transporte/protocolo, sesiones, breakpoints persistentes, threads/frames, variables, evaluación, REPL y fuentes generadas. Migrar todos los adaptadores, launch/VSCode, virtual text y listeners FOX, incluidas correcciones js-debug. Verificar adaptadores reales por transporte y plataforma, respuestas fuera de orden, attach/desconexión y limpieza de procesos. |
| 22 | `folke/lazy.nvim` | Súper difícil | Baja | Es el bootstrap y el contrato de todas las specs, incluidas 73 locales: imports, mezcla, dependencias, eventos/comandos/teclas/filetypes, opts/config e introspección/cargas explícitas. Posponer hasta estabilizar los demás reemplazos; aprovechar paquetes nativos donde sirvan. Conservar lock/pins, instalación/actualización y recuperación de errores para los externos que aún existan; probar arranque limpio y migración sin red. |

### Orden de ejecución propuesto

1. **Primero, los más susceptibles (1–5).** Consolidar file-browser, resolver el catálogo de schemas, conectar previews sin Snacks, completar defaults LSP y sustituir formato. Los tres primeros tienen alcance menor que su clasificación antigua. LSP y Conform aprovechan los módulos por lenguaje, pero necesitan pruebas reales antes de quitar defaults externos.
2. **Después, funciones difíciles y delimitadas (6–10).** Cord, render Markdown, signos Git, Diffview y preview web. Mantener cada cambio independiente. No cambiar render en editor y preview en navegador a la vez; son dos comportamientos distintos. Si falta Discord o una plataforma necesaria, registrar el bloqueo de esa fila y continuar con otra elegible, sin declarar paridad no probada.
3. **Luego, interfaces e integraciones grandes (11–17).** DAP UI permite retirar Nio; Neo-tree permite retirar Nui; migrar Neogit y Telescope reduce los consumidores de Plenary. Priorizar retirar una biblioteca ya huérfana sobre reescribir su API. Diffview debe tener resuelta su integración antes de eliminarlo; Telescope conserva prioridad sobre Plenary mientras este siga siendo necesario.
4. **Al final, infraestructura súper difícil (18–22).** Gestor/recursos Treesitter, distribución de herramientas Mason, completion, motor DAP y gestor Lazy. Antes de cada uno, acotar la matriz real de funciones y plataformas y estimar su mantenimiento. Un módulo nativo disponible reduce trabajo, pero no acredita por sí solo un reemplazo completo. Lazy queda último porque gobierna la carga del resto.

### Comprobaciones para dar por terminado cada pendiente

- Revisar spec, lockfile, comandos/paleta, consumidores locales y transitivos, datos persistidos, tests/fixtures y documentación afectada. No borrar directorios instalados ni atribuciones.
- Añadir cobertura enfocada del comportamiento observable y fallos relevantes. Para UI, edición, LSP, DAP, IPC o parsers, completar las integraciones reales que correspondan; fixtures de plataforma no equivalen a ejecutarla físicamente.
- Ejecutar tests con `--only-failure`, sintaxis y lint/formato aplicables al código cambiado. Documentar fallos previos y comprobaciones pendientes; no marcar completo con un consumidor aún externo o una integración imprescindible sin verificar.
- Actualizar esta tabla, notas históricas e inventario solo después de retirar de verdad la dependencia. Una retirada transitiva cuenta como dependencia eliminada, pero no como una implementación nueva de su biblioteca.

### Límites de esta reevaluación

Es análisis estático del checkout e instalaciones locales, no una auditoría exhaustiva de las 22 implementaciones ni de sus últimas versiones remotas. No se ejecutaron sesiones interactivas, pruebas de rendimiento, instalaciones, Discord, navegadores ni adaptadores en esta revisión. Las dificultades son relativas y se deben confirmar al iniciar cada reemplazo; no son estimaciones de tiempo. Se mantienen intactos los resultados históricos de validación que siguen debajo.

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

## Reemplazo 22: akinsho/bufferline.nvim

- Tabline nativa propia en `fox.ui.tabline`: separadores inclinados, texto blanco para buffers seleccionados/visibles, iconos, modificaciones, diagnósticos, nombres duplicados y marcador de borrado `[D]`. Overflow con contadores clicables y prioridad para el buffer activo y los fijados; offset de Neo-tree, badge de workspace e indicadores de tabpages.
- Conserva filtros de Environments/Query y representación de previews multimedia; selección en ventana de código, cierre por botón/clic medio/derecho mediante Smart_Close_Buffer, sin forzar borrado de cambios sin guardar. Comandos de ciclo, movimiento, selección, cierre y pin conservados; acciones de navegación/selección/movimiento en paleta, sin nuevos leader mappings.
- Pins siguen en `.foxnvim/pins.json` y `pins_<id>.json`; restauración y consumidores locales migrados a la API nativa. Un fallo al guardar impide cambiar el pin visible. Conserva `g:BufferlinePositions` para el orden de sesiones. Se mantienen los highlights BufferLine que consume Git Center.
- Siete pruebas de tabline y ocho de pins aprobadas (incluida la restauración antes desactivada). Tres integraciones reales: Neo-tree/badge/foco, cierre del último archivo al dashboard y eventos de ratón en un editor RPC con UI adjunta; verifican selección, protección de cambios, clic medio/derecho y botón de cierre. Suite completa: 911 aprobadas, con los mismos dos fallos preexistentes en autotag TSX y aislamiento del tema Ryoku ya reproducidos en el commit inicial del reemplazo anterior.
- Syntax: 832 archivos sin errores; StyLua/Luacheck aprobados en los archivos Lua modificados. Registro Lazy: 27 externos y 70 locales. No se probó Windows/WSL aquí ni se eliminaron directorios de plugins instalados.

## Reemplazo 23: rafamadriz/friendly-snippets

- Recursos JSON conservados localmente en `config/snippet_catalog/`: 143 archivos, 6.194 definiciones y 129 filetypes/aliases. Verificados byte por byte contra el commit bloqueado b4d01b0fdf3c9a549961c2f9ffe8dc09be166219; manifiesto con idénticas contribuciones y orden. Son datos upstream atribuidos, no código FOX reescrito; licencia MIT en `licenses/friendly-snippets.txt`, origen y actualización manual documentados junto al catálogo.
- Carga propia en `fox.lsp.snippets` sobre el motor de Blink/Neovim existente: mantiene variables, tabstops, mirrors y expansión nativa. Los prefijos personalizados sustituyen sugerencias del catálogo; schema y entradas inválidas no rompen el menú. Retirada la dependencia y el lockfile; desactivado el descubrimiento automático de friendly-snippets y retirado el parche global sobre Blink.
- Snippet Manager conserva archivos y comandos. Guardar JSON, escribir desde el manager o ejecutar FoxSnippetReload rescanea también archivos nuevos sin reiniciar Blink. Las instalaciones mínimas no cambian; no se instalan bundles opcionales ni se eliminan carpetas de plugins instalados.
- Dos pruebas unitarias y cinco integraciones reales aprobadas. Paridad con la carga nativa de Blink para los 129 filetypes/aliases; overrides, entradas inválidas, JSON inválido, archivos nuevos/eliminados, recarga del proveedor activo y expansión con tabstops reales verificados. Registro Lazy: 26 externos y 70 locales. No se ejecutó Windows/WSL aquí.

- Validación final: 835 archivos Lua sin errores de sintaxis; StyLua/Luacheck sin advertencias en los cinco archivos Lua de este reemplazo. Suite completa: 914 aprobadas y los dos fallos preexistentes en autotag TSX y aislamiento del tema Ryoku. El commit inicial d8b3436 también abortaba por una aserción de grid de Neovim; corregida por separado en c046d67 al probar anchos pequeños sin redimensionar el editor.

## Reemplazo 24: rcarriga/nvim-notify

- Motor local compartido en `fox.core.notify`, con cola acotada por el espacio disponible, animación desktop, modo móvil compacto/estático, límites por celdas Unicode, historial de sesión, IDs de reemplazo y un único timer cancelable. No toma foco al abrir ni al copiar; cambios de tamaño redistribuyen/reencolan ventanas sin perder mensajes.
- Feature adicional solicitada: un clic izquierdo copia el mensaje completo de esa notificación al registro `+` de Neovim y la cierra. Funciona con el proveedor de clipboard configurado en Windows/Linux; no usa comandos shell específicos del sistema. El texto original se conserva aunque la ventana lo trunque. Un error de copia mantiene el mensaje disponible.
- Conserva NotifyCopyLast, NotifyDismiss, ClearToasts, Notifications y NotificationsClear; acciones de paleta, picker Telescope propio y entrada local `require("notify")`. Progreso de DocManager y Neo-tree comparte motor con vim.notify; soporta timeout=false, keep, reemplazos, callbacks e historial oculto. Retirados declaración externa y lockfile; ningún código upstream copiado ni directorio instalado eliminado.
- Trece pruebas unitarias relacionadas y tres integraciones reales aprobadas: registro/comandos, picker Telescope y clic mediante editor RPC con UI real y proveedor de clipboard controlado. Verifican texto completo de la notificación seleccionada, cierre individual, foco, resize, expiración, animación, cola, progreso y callbacks. No se ejecutó un escritorio Windows aquí.

- Validación final: 924 pruebas aprobadas y los mismos dos fallos preexistentes (autotag TSX y aislamiento del selector de temas). 839 archivos Lua sin errores de sintaxis; StyLua y Luacheck aprobados para los nueve archivos Lua del cambio. Inventario verificado desde Lazy: 25 externos y 71 specs locales.

## Reemplazo 25: windwp/nvim-autopairs

- Implementación original en `fox.editor.autopairs`, con mappings expr y operaciones nativas de inserción: pares básicos, salto de cierres balanceados, borrado conjunto, Enter e indentación, envoltura de argumentos entre comillas, cercas Markdown, comillas triples, strings Nix y comentarios HTML. No se copia código upstream ni se eliminan directorios instalados.
- Undo/redo conserva inserciones atómicas y movimientos sin cortar el bloque; macros y modo reemplazo permanecen literales. Respeta buffers no modificables, flotantes sin filetype y exclusiones TelescopePrompt/vim. Treesitter excluye strings/comentarios con fallback sin parser y se desactiva solo en Termux nativo; proot mantiene la detección.
- Spec local eager pequeña, anterior a Blink, para que sus fallbacks de BS/Enter capturen los mappings correctos. Completion manual dentro de pares vacíos y expansión de snippets continúan en Blink/Neovim, sin hooks de completion adicionales ni instalaciones opcionales.
- Diez pruebas enfocadas y siete integraciones aprobadas, incluida UI RPC con Blink real: menú manual dentro de pares, aceptación por Enter de un snippet con tabstops, Unicode, macros, reemplazo, indentación y undo/redo. Diez pruebas de entorno/configuración aprobadas. Windows/WSL y Termux físicos no ejecutados; gating de Termux/proot verificado con fixtures.

- Validación final: 934 pruebas aprobadas y dos fallos preexistentes (autotag TSX y aislamiento del selector de temas), reproducidos en una copia limpia del commit inicial `20d434f` (924 aprobadas y los mismos dos fallos). 842 archivos Lua sin errores de sintaxis; StyLua/Luacheck sin advertencias en los cinco archivos Lua del cambio. Registro Lazy verificado: 24 externos y 72 specs locales.

## Reemplazo 26: vuki656/package-info.nvim

- Implementación original en `fox.langs.typescript.packages`; configuración del ecosistema en `fox.langs.typescript.package_info`. Conserva ocho comandos PackageInfo y la entrada `require("package-info")`; ocho acciones nuevas de paleta, sin nuevos leader mappings. Las referencias antiguas a leader ns/nc no correspondían a mappings registrados.
- Consultas manuales asíncronas, cuatro simultáneas, timeout y caché de sesión por proyecto. Versiones ordenadas, filtro de prereleases y etiqueta `latest`; parser JSON con posiciones exactas que excluye scripts y objetos anidados, diagnósticos de duplicados/valores inválidos. No ejecuta gestores al abrir archivos ni necesita yq para mostrar referencias de catálogo.
- Detecta gestores en manifiestos y lockfiles cercanos/ancestros; npm/pnpm/Yarn/Bun para cambios, npm/pnpm para registro como antes. Argumentos separados, nombres validados y cwd del manifiesto; adaptadores de entrada Node para Windows y rutas WSL. Dependencias dev conservan su sección; referencias locales/workspace/catalog/alias no se convierten inadvertidamente en paquetes de registro.
- Prompts cancelables con vim.ui; revalida buffer y disco antes de mutar, serializa cambios por workspace y preserva ediciones concurrentes. El gestor mantiene manifiesto/lockfiles; tras éxito o error recarga solo buffers intactos. Se conserva Nui para Neo-tree y se retiran únicamente la dependencia y su lockfile; no se eliminan directorios instalados ni se instala tooling opcional.
- Trece pruebas enfocadas y cuatro integraciones reales aprobadas. Registro npm HTTP local y tarballs temporales prueban consulta, caché, latest, update, versión estable, delete y lockfile con npm; Bun instala una dependencia dev y escribe bun.lock. Fixtures verifican cancelación, fallos de red/JSON/proceso, respuestas tardías, concurrencia, límites y construcción Windows/WSL. No se ejecutaron gestores nativos de Windows ni Yarn/pnpm reales en esta máquina.
- Suite completa: 947 aprobadas y los dos fallos preexistentes en autotag TSX y aislamiento del selector de temas (934 aprobadas y los mismos fallos antes del cambio). 846 archivos Lua sin errores de sintaxis; StyLua/Luacheck aprobados en los siete archivos Lua del reemplazo. Inventario verificado: 23 externos y 73 specs locales.

## Reemplazo 27: m00qek/baleia.nvim

- Implementación original en `fox.dap.ansi`, integrada en la configuración DAP existente, sin nueva spec. Parser incremental por líneas con estado de estilos y escapes incompletos; colores 16/256/RGB, atributos y resets, eliminación de CSI/OSC y enlaces OSC. No emula movimientos de terminal.
- Conserva códigos y checkpoints al anexar salida sobre líneas ya limpiadas, recalcula desde la región modificada y agrupa escrituras rápidas. Extmarks con columnas de bytes Unicode; respeta buffers no modificables, cambios de tema, borrado/reload y cancelación de trabajo pendiente al eliminar un buffer. Usa set_text por fila para conservar la marca de prompt de nvim-dap.
- Se retiran solo la declaración y el lockfile de Baleia; no se eliminan plugins instalados ni se añaden instalaciones opcionales. Inventario: 22 externos y las mismas 73 specs locales.
- Siete pruebas enfocadas y dos integraciones reales aprobadas en Windows con nvim-dap y buffers dapui_console: escapes fragmentados, appends, Unicode, estilos, clear, readonly, temas y eliminación. Sin adaptador remoto ni sesión interactiva de depuración.
- Suite completa: 964 aprobadas y nueve fallos preexistentes de rutas Windows y sysfs Linux; copia del commit 606135a: 958 aprobadas y los mismos nueve fallos. Sintaxis: 854 archivos sin errores. StyLua/Luacheck aprobados para los cuatro archivos Lua del reemplazo.

## Siguiente ítem

`nvim-telescope/telescope-file-browser.nvim`: primer candidato de la nueva tabla `Pendientes`. Comenzar por comprobar la entrada pública de la extensión y consolidarla con el explorador FOX. Cord pasa a la posición 6. Ningún reemplazo iniciado: la petición actual autoriza mejorar el plan solamente.
