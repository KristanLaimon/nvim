# DataGrip de JetBrains: inventario de funcionalidades

Fecha de consulta: **22 de octubre de 2026**. Referencia principal: documentación oficial de **DataGrip 2026.2** y páginas de funcionalidades de JetBrains.

Este documento reúne las funcionalidades identificadas y verificadas en las fuentes oficiales consultadas. Busca cubrir el producto con amplitud; no representa un catálogo contractual de cada acción, inspección o plugin existente. La disponibilidad concreta depende de la versión, el motor, el controlador, los permisos y los complementos habilitados.

## Índice

1. [Qué es DataGrip](#1-qué-es-datagrip)
2. [Bases de datos compatibles](#2-bases-de-datos-compatibles)
3. [Conexiones y controladores](#3-conexiones-y-controladores)
4. [Conectividad segura y nube](#4-conectividad-segura-y-nube)
5. [Explorador e introspección](#5-explorador-e-introspección)
6. [Búsqueda y navegación](#6-búsqueda-y-navegación)
7. [Editor SQL inteligente](#7-editor-sql-inteligente)
8. [Inspecciones y correcciones](#8-inspecciones-y-correcciones)
9. [Refactorización](#9-refactorización)
10. [Formato y plantillas](#10-formato-y-plantillas)
11. [Ejecución de consultas y scripts](#11-ejecución-de-consultas-y-scripts)
12. [Sesiones y transacciones](#12-sesiones-y-transacciones)
13. [Resultados y edición de datos](#13-resultados-y-edición-de-datos)
14. [Relaciones reales y virtuales](#14-relaciones-reales-y-virtuales)
15. [Análisis y visualización](#15-análisis-y-visualización)
16. [Comparación de datos](#16-comparación-de-datos)
17. [Objetos, DDL y generación SQL](#17-objetos-ddl-y-generación-sql)
18. [Comparación y migración de esquemas](#18-comparación-y-migración-de-esquemas)
19. [Diagramas y esquemas sin conexión](#19-diagramas-y-esquemas-sin-conexión)
20. [Importación, exportación y respaldos](#20-importación-exportación-y-respaldos)
21. [Planes de ejecución](#21-planes-de-ejecución)
22. [Procedimientos y depuración](#22-procedimientos-y-depuración)
23. [Inteligencia artificial y agentes](#23-inteligencia-artificial-y-agentes)
24. [Archivos, historial y control de versiones](#24-archivos-historial-y-control-de-versiones)
25. [Personalización, terminal y automatización](#25-personalización-terminal-y-automatización)
26. [Novedades destacadas de 2026.2](#26-novedades-destacadas-de-20262)
27. [Límites importantes](#27-límites-importantes)

## 1. Qué es DataGrip

- IDE dedicado al trabajo con bases de datos relacionales y NoSQL.
- Entorno único para escribir SQL, ejecutar consultas, editar datos y trabajar con estructuras.
- Gestión de múltiples motores y conexiones dentro de un mismo proyecto.
- Aplicación para Windows, macOS y Linux.
- Runtime Java incluido en la distribución.
- Funcionalidad de bases de datos disponible también mediante Database Tools and SQL en otros IDE de JetBrains compatibles.

Fuentes: [visión general](https://lp.jetbrains.com/datagrip/features-overview/) e [instalación](https://www.jetbrains.com/help/datagrip/installation-guide.html).

## 2. Bases de datos compatibles

### 2.1 Soporte completo

Incluye asistencia específica del dialecto, introspección especializada y funciones de análisis de código. La lista oficial consultada contiene:

| Familia | Motores y servicios |
|---|---|
| Relacionales habituales | PostgreSQL, MySQL, MariaDB, Oracle, Microsoft SQL Server, SQL Server LocalDB, SQLite |
| Relacionales y analíticos adicionales | IBM Db2 LUW, Sybase ASE, H2, HSQLDB, Apache Derby, CockroachDB, Greenplum, Exasol, Vertica |
| Analítica y almacenes de datos | Amazon Redshift, Google BigQuery, Snowflake, ClickHouse, Apache Hive |
| Documentos, claves y otros modelos | MongoDB, Amazon DocumentDB, Amazon DynamoDB, Redis, Apache Cassandra, Couchbase Query Service |
| SQL administrado | Azure SQL Database |

Fuente: [motores compatibles y rangos de versiones](https://www.jetbrains.com/help/datagrip/managing-data-sources.html).

### 2.2 Soporte básico

Amazon Athena, Apache Ignite, Apache Phoenix, Apache Spark, Databricks, Denodo, DuckDB, Elasticsearch, Firebird, Google Cloud Spanner, IBM Informix, InterSystems IRIS, Mimer SQL, OpenEdge, Presto, SAP HANA, SingleStore, Tarantool, Teradata Vantage, TiDB, TmaxTibero, Trino y YugabyteDB.

- Conexión mediante el controlador correspondiente.
- Exploración de los objetos expuestos por los metadatos JDBC.
- Resaltado con el dialecto SQL 2016.
- Posibilidad de añadir controladores propios para otros motores.
- Menor asistencia específica: no incluye el análisis de errores ni toda la introspección del soporte completo.

Fuente: [bases de datos con soporte básico](https://www.jetbrains.com/help/datagrip/other-databases.html).

## 3. Conexiones y controladores

- Crear fuentes de datos con los parámetros de conexión de cada motor.
- Mantener varias conexiones a motores y entornos distintos.
- Comprobar la conexión antes de empezar a trabajar.
- Configurar controladores JDBC y sus propiedades.
- Usar controladores personalizados cuando sea necesario.
- Copiar y pegar fuentes de datos para reutilizar configuraciones.
- Reutilizar conexiones entre proyectos y otros IDE de JetBrains.
- Crear configuraciones reutilizables mediante plantillas de fuentes de datos.
- Organizar conexiones y objetos mediante carpetas, filtros y colores.

Fuentes: [fuentes de datos](https://www.jetbrains.com/help/datagrip/managing-data-sources.html), [soporte mediante controladores](https://www.jetbrains.com/help/datagrip/other-databases.html) y [gestión de bases de datos](https://lp.jetbrains.com/datagrip/databases/).

## 4. Conectividad segura y nube

- Túneles SSH creados desde el IDE.
- Uso de túneles SSH configurados externamente.
- Autenticación SSH mediante contraseña o pares de claves.
- Integración con configuración OpenSSH y agentes de autenticación compatibles.
- Conexiones SSL con certificados y opciones de verificación del servidor.
- Reutilización de configuraciones SSH y SSL entre fuentes de datos.
- Descubrimiento de bases de datos desde cuentas de AWS, Google Cloud y Azure.
- Creación de fuentes de datos con los parámetros obtenidos del proveedor de nube.
- Integración con Azure Cloud Explorer para el flujo de Azure.

Fuentes: [SSH y SSL](https://www.jetbrains.com/help/datagrip/configuring-ssh-and-ssl.html) y [proveedores de nube](https://www.jetbrains.com/help/datagrip/clouds.html).

## 5. Explorador e introspección

- Árbol de bases de datos, esquemas y objetos mediante Database Explorer.
- Exploración de tablas, columnas, vistas, índices, claves y rutinas disponibles en cada motor.
- Lectura de metadatos para alimentar autocompletado, navegación y generación DDL.
- Introspección completa, fragmentaria o incremental cuando el motor lo permite.
- Actualización de los metadatos y del árbol de objetos.
- Selección del alcance de introspección para trabajar con los esquemas necesarios.
- Filtros para reducir los objetos visibles.
- Agrupación, ordenación y presentación configurable del árbol.
- Colores para distinguir conexiones y carpetas.
- Acceso a acciones de datos, estructura, diagramas y SQL desde cada objeto.

Fuentes: [metadatos e introspección](https://www.jetbrains.com/help/datagrip/introspection.html) y [Database Explorer](https://www.jetbrains.com/help/datagrip/database-explorer.html).

## 6. Búsqueda y navegación

- Buscar objetos de base de datos entre los elementos introspeccionados.
- Buscar archivos, símbolos y acciones desde el IDE.
- Navegar entre el código SQL y los objetos referenciados.
- Examinar la estructura de scripts extensos.
- Buscar texto dentro de archivos y proyectos.
- Buscar datos mediante búsqueda de texto completo y filtros de filas.
- Localizar texto en las cuadrículas, con expresiones regulares cuando corresponda.
- Saltar entre registros relacionados por claves foráneas.

Fuentes: [búsqueda en DataGrip](https://www.jetbrains.com/help/datagrip/search-in-ide.html), [estructura del código](https://www.jetbrains.com/help/datagrip/code-structure.html) y [exploración de datos](https://lp.jetbrains.com/datagrip/working-with-data/).

## 7. Editor SQL inteligente

- Resaltado de sintaxis según el dialecto seleccionado.
- Autocompletado de tablas, columnas, objetos, parámetros y palabras clave.
- Sugerencias ajustadas al contexto y al alcance visible.
- Información de contexto para nombres ambiguos.
- Propuestas de `JOIN` basadas en claves foráneas.
- Completado de campos en sentencias `INSERT`.
- Sugerencias mediante abreviaturas y compatibilidad con distribuciones de teclado no inglesas.
- Finalización de construcciones sintácticas.
- Inserción de fragmentos mediante plantillas dinámicas.
- Plegado, selección, duplicado y movimiento de bloques o líneas de código.
- Comentado y reformateo desde las acciones del editor.

Fuentes: [asistencia SQL](https://lp.jetbrains.com/datagrip/sql-support/), [autocompletado](https://www.jetbrains.com/help/datagrip/auto-completing-code.html) y [edición de SQL](https://www.jetbrains.com/help/datagrip/work-with-sql-code.html).

## 8. Inspecciones y correcciones

- Análisis del código mientras se escribe.
- Resaltado de errores y problemas detectables antes de ejecutar.
- Detección de referencias no resueltas y posibles errores SQL.
- Detección de código muerto y otros problemas según las inspecciones disponibles.
- Sugerencias de corrección rápida.
- Advertencias ante operaciones potencialmente peligrosas.
- Inspección del proyecto completo o de un alcance concreto.
- Activación y desactivación de inspecciones individuales.
- Niveles de severidad configurables.
- Perfiles de inspección y vista de problemas del archivo.

Fuentes: [inspecciones](https://www.jetbrains.com/help/datagrip/code-inspection.html), [panel de problemas](https://www.jetbrains.com/help/datagrip/problems-tool-window.html) y [asistencia SQL](https://lp.jetbrains.com/datagrip/sql-support/).

## 9. Refactorización

- Renombrar objetos de base de datos desde el editor.
- Renombrar elementos del código y actualizar sus usos reconocidos.
- Renombrar tablas, columnas y alias en los contextos compatibles.
- Previsualizar referencias y cambios antes de aplicar una refactorización.
- Elegir si se incluyen coincidencias en comentarios, cadenas y otras apariciones textuales.
- Sugerencias de actualización de usos al cambiar nombres directamente en el código.
- Extracción de variables en los contextos admitidos.

El alcance depende del dialecto y del código que DataGrip puede analizar; no equivale a actualizar automáticamente aplicaciones externas.

Fuentes: [refactorización](https://www.jetbrains.com/help/datagrip/refactoring-source-code.html) y [refactorización SQL](https://lp.jetbrains.com/datagrip/sql-support/).

## 10. Formato y plantillas

- Reformatear SQL con un estilo definido.
- Mantener esquemas de estilo a nivel de proyecto o de IDE.
- Compartir el estilo del proyecto mediante control de versiones.
- Configurar y reutilizar varios esquemas de estilo del IDE.
- Usar plantillas dinámicas incorporadas para fragmentos repetitivos.
- Crear plantillas dinámicas propias.
- Crear archivos a partir de plantillas personalizadas.
- Configurar plantillas de nombres generados para claves e índices.

Fuentes: [estilo de código](https://www.jetbrains.com/help/datagrip/configuring-code-style.html), [plantillas de archivos](https://www.jetbrains.com/help/datagrip/using-file-and-code-templates.html), [plantillas SQL](https://lp.jetbrains.com/datagrip/sql-support/) y [nombres de claves e índices](https://www.jetbrains.com/help/datagrip/foreign-keys.html).

## 11. Ejecución de consultas y scripts

- Ejecutar una sentencia, una selección o un script completo.
- Elegir la sentencia o subconsulta que corresponde ejecutar según la posición del cursor.
- Trabajar con varios archivos y consolas de consulta.
- Cambiar el esquema de trabajo desde el entorno de consultas.
- Ejecutar archivos SQL contra una fuente de datos.
- Asociar archivos de consulta con una fuente de datos y guardarlos en el proyecto.
- Proporcionar valores para parámetros de usuario antes de ejecutar.
- Configurar patrones de reconocimiento de parámetros.
- Consultar, editar y volver a ejecutar sentencias del historial.
- Revisar resultados y mensajes de ejecución.
- Recibir notificaciones al terminar consultas largas, según la configuración.

Fuentes: [ejecutar consultas](https://www.jetbrains.com/help/datagrip/run-a-query.html), [opciones de ejecución](https://www.jetbrains.com/help/datagrip/query-execution.html) y [archivos de consulta](https://www.jetbrains.com/help/datagrip/query-files.html).

## 12. Sesiones y transacciones

- Administrar sesiones y sus conexiones desde Services.
- Asociar archivos y editores de datos a sesiones.
- Compartir una sesión entre varios clientes cuando se necesita el mismo contexto.
- Usar sesiones dedicadas o una sesión compartida.
- Separar la introspección del trabajo habitual mediante el modo de dos sesiones de 2026.2.
- Seleccionar el modo de transacciones automático o manual.
- Confirmar cambios con `COMMIT` o revertir con `ROLLBACK` cuando el motor y la transacción lo permitan.
- Elegir el nivel de aislamiento disponible.
- Activar el modo de solo lectura de la fuente de datos.
- Recibir avisos antes de operaciones como modificaciones masivas sin un filtro adecuado.

Fuentes: [sesiones](https://www.jetbrains.com/help/datagrip/managing-connection-sessions.html), [controles del editor](https://www.jetbrains.com/help/datagrip/code-editor.html), [ejecución y protección](https://lp.jetbrains.com/datagrip/running-queries/) y [novedades 2026.2](https://www.jetbrains.com/help/datagrip/release-notes-datagrip.html).

## 13. Resultados y edición de datos

- Cuadrícula para tablas, resultados de consultas y archivos de datos compatibles.
- Visualización de resultados en un panel dedicado o debajo del SQL dentro del editor.
- Pestañas de resultados identificables mediante nombres definidos en comentarios SQL.
- Paginación y límites de filas para controlar la cantidad de datos cargados.
- Ordenación en el servidor o en el cliente según el tipo de resultado.
- Filtrado mediante condiciones y expresiones SQL.
- Búsqueda de texto dentro de los datos.
- Añadir, eliminar, copiar y editar filas.
- Editar varias celdas y pegar datos desde el portapapeles.
- Establecer valores `NULL` o `DEFAULT`.
- Abrir el contenido de una celda en un editor de valores independiente.
- Ajustar cómo se presentan determinados datos binarios.
- Revisar o revertir cambios pendientes antes de enviarlos.
- Consultar la sentencia que generó la vista de datos y copiarla a una consola.
- Utilizar expresiones SQL como valor de celda en 2026.2.

Fuentes: [editor y visor de datos](https://www.jetbrains.com/help/datagrip/data-editor-and-viewer.html), [resultados integrados](https://lp.jetbrains.com/datagrip/running-queries/) y [expresiones SQL en celdas](https://www.jetbrains.com/help/datagrip/release-notes-datagrip.html).

## 14. Relaciones reales y virtuales

- Reconocer claves foráneas declaradas en la base de datos.
- Usar relaciones para proponer uniones, navegar y dibujar diagramas.
- Abrir filas referenciadas o filas que hacen referencia al registro seleccionado.
- Navegar desde varios valores seleccionados a sus datos relacionados.
- Crear claves foráneas con previsualización del SQL correspondiente.
- Definir claves foráneas virtuales en el IDE.
- Guardar relaciones virtuales y configurar reglas basadas en expresiones regulares.

Una clave virtual ayuda a trabajar en DataGrip, pero no crea una restricción de integridad referencial en el servidor.

Fuentes: [claves foráneas](https://www.jetbrains.com/help/datagrip/foreign-keys.html) y [claves foráneas virtuales](https://www.jetbrains.com/help/datagrip/virtual-foreign-keys.html).

## 15. Análisis y visualización

- Calcular agregaciones sobre las celdas seleccionadas.
- Obtener conteo, suma, promedio, mínimos y máximos.
- Crear agregaciones propias.
- Generar gráficos interactivos a partir de datos.
- Visualizar series mediante gráficos de barras, líneas y sectores.
- Exportar gráficos como imágenes PNG.
- Explorar datos geográficos compatibles mediante Geo Viewer.
- Mostrar información espacial sobre un mapa.

Fuentes: [análisis de datos](https://lp.jetbrains.com/datagrip/working-with-data/), [exploración en el editor](https://www.jetbrains.com/help/datagrip/explore-data-in-data-editor.html) y [visualización de datos](https://www.jetbrains.com/help/datagrip/tables-view-data.html).

## 16. Comparación de datos

- Comparar el contenido de dos tablas.
- Comparar salidas de vistas y vistas materializadas.
- Comparar resultados desde el editor o desde el explorador.
- Comparar objetos de tipos distintos cuando tienen datos comparables.
- Mostrar diferencias de filas y celdas en paralelo.
- Configurar tolerancia para considerar equivalentes filas con ciertas diferencias.
- Ajustar el tratamiento de columnas adicionales.

La comparación depende del conjunto de filas cargado y de los límites configurados; no debe asumirse que siempre examina una tabla completa.

Fuente: [comparación de datos](https://www.jetbrains.com/help/datagrip/compare-data.html).

## 17. Objetos, DDL y generación SQL

- Crear y modificar tablas desde una interfaz visual.
- Añadir o cambiar columnas, índices y restricciones.
- Previsualizar el DDL que producirá una modificación.
- Aplicar el cambio o conservar su script para ejecutarlo después.
- Generar DDL para objetos individuales o esquemas completos.
- Copiar DDL al portapapeles, abrirlo en una consola o guardarlo.
- Distribuir la salida en archivos por objeto, esquema, base de datos o tipo.
- Recuperar el DDL original almacenado por el servidor cuando esté disponible.
- Insertar plantillas de creación de tablas, funciones, procedimientos y triggers.
- Generar scripts de ejecución de procedimientos y funciones.
- Generar sentencias DML a partir de datos y modificaciones mediante las opciones correspondientes.

Fuentes: [generación SQL y editor de estructuras](https://lp.jetbrains.com/datagrip/sql-support/) y [exportación de estructuras](https://www.jetbrains.com/help/datagrip/export-data.html).

## 18. Comparación y migración de esquemas

- Comparar objetos del mismo tipo: esquemas, tablas o rutinas.
- Comparar estructuras alojadas en servidores distintos.
- Distinguir objetos añadidos, modificados y eliminados.
- Revisar diferencias de propiedades o de DDL.
- Mostrar también los elementos idénticos si se desea.
- Generar un script para que el destino adopte la estructura del origen.
- Incluir o excluir cambios concretos de la migración.
- Editar y revisar el script antes de aplicarlo.
- Ejecutarlo desde el diálogo o abrirlo en una consola.

La comparación estructural y la comparación de datos son funciones diferentes.

Fuente: [comparación y migración de esquemas](https://www.jetbrains.com/help/datagrip/schema-comparison-and-migration.html).

## 19. Diagramas y esquemas sin conexión

### Diagramas

- Generar diagramas desde fuentes de datos, esquemas o tablas.
- Visualizar tablas y relaciones entre objetos.
- Mostrar u ocultar columnas y claves en la representación.
- Guardar diagramas en el formato interno UML de DataGrip.
- Exportar imágenes PNG para compartirlos.
- Acceder a otras opciones de exportación según el visor y la versión.

Fuentes: [diagramas de bases de datos](https://www.jetbrains.com/help/datagrip/creating-diagrams.html) y [ajustes de diagramas](https://www.jetbrains.com/help/datagrip/diagrams.html).

### Fuentes de datos DDL

- Construir una representación virtual del esquema a partir de archivos SQL DDL.
- Navegar por tablas, columnas y objetos definidos en esos archivos.
- Obtener referencias y asistencia del editor sin necesitar una conexión activa al servidor.
- Generar diagramas de esa estructura virtual.
- Crear una fuente DDL a partir de una base existente o archivos previos.
- Actualizar la representación al cambiar los archivos.
- Filtrar los archivos que forman parte de la fuente.
- Versionar la estructura mediante SQL almacenado en Git u otro VCS.
- Configurar DDL mappings para relacionar fuentes de datos con sus archivos DDL.

Fuentes: [fuentes DDL](https://www.jetbrains.com/help/datagrip/ddl-data-sources.html), [bases de datos en control de versiones](https://www.jetbrains.com/help/datagrip/databases-in-the-version-control-system.html) y [DDL mappings](https://www.jetbrains.com/help/datagrip/ddl-mappings.html).

## 20. Importación, exportación y respaldos

### Importar y copiar

- Importar CSV, TSV y otros formatos delimitados.
- Importar archivos tabulares compatibles, incluidos los formatos habilitados mediante cargadores.
- Importar JSON y Excel mediante los flujos compatibles descritos por JetBrains.
- Ejecutar archivos SQL para cargar datos o estructuras.
- Importar a una tabla nueva o existente.
- Configurar correspondencias de columnas, conversiones y encabezados.
- Previsualizar datos y opciones antes de confirmar una importación.
- Iniciar importaciones arrastrando archivos al esquema o tabla.
- Copiar tablas a otros esquemas o bases de datos.
- Copiar datos o materializar resultados como tablas, incluso entre motores distintos cuando la conversión lo permite.

Fuentes: [importación](https://www.jetbrains.com/help/datagrip/import-data.html), [archivos y formatos](https://lp.jetbrains.com/datagrip/working-with-files/) y [copia entre bases](https://lp.jetbrains.com/datagrip/working-with-data/).

### Exportar

- Exportar tablas y resultados a archivos o al portapapeles.
- Exportar datos como CSV, TXT, JSON, XML, HTML, Markdown y Excel, entre otros formatos disponibles.
- Utilizar extractores incorporados.
- Definir formatos CSV/DSV propios.
- Crear extractores personalizados mediante la API proporcionada.
- Ajustar encabezados y transposición de la salida.
- Exportar estructuras y datos por separado.

Fuente: [exportación y extractores](https://www.jetbrains.com/help/datagrip/export-data.html).

### Dumps y restauración

- Integración con herramientas nativas como `mysqldump`, `pg_dump` y `psql`.
- Crear dumps de MySQL y PostgreSQL desde el entorno del IDE.
- Restaurar datos mediante los flujos y herramientas compatibles.

Estos flujos requieren disponer de las herramientas externas correspondientes; no constituyen un sistema universal de respaldos para todos los motores.

Fuentes: [dumps y restauración desde DataGrip](https://lp.jetbrains.com/datagrip/working-with-files/) y [dumps completos](https://www.jetbrains.com/help/datagrip/export-data.html).

## 21. Planes de ejecución

- Solicitar el plan de una consulta mediante Explain Plan.
- Ejecutar Explain Analyse en los motores que lo admiten.
- Examinar recorridos de tablas, algoritmos de unión y costos estimados.
- Consultar estadísticas reales cuando se utiliza análisis con ejecución.
- Ver planes como árbol, tabla o diagrama.
- Consultar el plan en su formato original o raw.
- Copiar el plan original en formatos como JSON o XML para los motores compatibles.
- Usar las representaciones para investigar cuellos de botella.

**Explain Analyse ejecuta realmente la sentencia**. Los costos estimados del plan no son tiempos medidos de ejecución.

Fuente: [planes de ejecución](https://www.jetbrains.com/help/datagrip/query-execution-plan.html).

## 22. Procedimientos y depuración

- Generar scripts para invocar procedimientos y funciones.
- Introducir parámetros para ejecutar rutinas compatibles.
- Depurar código Oracle PL/SQL.
- Colocar puntos de interrupción.
- Avanzar línea por línea y entrar o salir de rutinas.
- Evaluar expresiones y observar variables.
- Depurar bloques anónimos, paquetes, procedimientos, funciones y triggers de Oracle.

**El depurador documentado está limitado a Oracle**. Requiere los privilegios correspondientes y compilación con información de depuración.

Fuentes: [ejecución de rutinas](https://lp.jetbrains.com/datagrip/sql-support/) y [depuración de Oracle](https://www.jetbrains.com/help/datagrip/debugging-code.html).

## 23. Inteligencia artificial y agentes

### Asistencia SQL

- Generar SQL desde peticiones en lenguaje natural.
- Utilizar el esquema como contexto para generar consultas.
- Explicar consultas y proponer mejoras.
- Completar SQL mediante asistencia en la nube cuando esté habilitada.
- Añadir objetos de base de datos al contexto del chat.
- Solicitar explicación de planes de ejecución.
- Pedir sugerencias de optimización basadas en la consulta y su plan.

Fuentes: [SQL e IA](https://lp.jetbrains.com/datagrip/sql-support/) y [uso de IA con bases de datos](https://www.jetbrains.com/help/ai-assistant/use-ai-with-databases.html).

### Agentes y herramientas

- Trabajar con agentes compatibles, incluidos los que JetBrains presenta para DataGrip, como Codex y Claude Agent.
- Explorar esquemas y metadatos desde el chat.
- Consultar muestras de datos y recuperar resultados adicionales cuando se permite.
- Generar y ejecutar consultas bajo los permisos configurados.
- Crear y modificar fuentes de datos mediante herramientas MCP.
- Probar conexiones y ayudar a diagnosticar errores de conexión.
- Extender agentes con instrucciones, skills y herramientas.
- Usar las skills `database-tools`, `database-connection-management` y `database-text-to-sql` documentadas en 2026.2.
- Revisar solicitudes de acceso y ejecución mediante los controles de consentimiento.

Las skills de bases de datos incorporadas están documentadas para el chat de IA, no para la CLI. Las herramientas MCP de bases de datos tienen sus propias condiciones de disponibilidad.

Fuentes: [agentes en DataGrip](https://www.jetbrains.com/help/datagrip/use-ai-agents-with-datagrip.html), [novedades de agentes y MCP](https://www.jetbrains.com/help/datagrip/release-notes-datagrip.html) y [controles de ejecución](https://lp.jetbrains.com/datagrip/running-queries/).

### JetBrains Air in IDEs — complemento separado

- Iniciar agentes locales o compatibles con ACP desde el IDE.
- Gestionar varias sesiones de agentes y seguir su progreso.
- Adjuntar contexto del proyecto, archivos, commits, imágenes y skills.
- Revisar cambios de archivos y aceptar, modificar o revertir lo producido.
- Crear preajustes de agente, modelo, esfuerzo y acceso.
- Usar la autorización y las cuentas compatibles con cada agente.

Disponible como plugin para versiones compatibles desde 2026.2; no sustituye a AI Assistant ni constituye por sí mismo un servicio de IA.

Fuente: [JetBrains Air in IDEs](https://www.jetbrains.com/help/datagrip/air-in-jetbrains-ides.html).

## 24. Archivos, historial y control de versiones

- Adjuntar carpetas locales al proyecto.
- Abrir, crear, organizar y editar archivos SQL, CSV, JSON y otros formatos.
- Trabajar con scripts y datos desde la misma interfaz.
- Guardar archivos de consulta dentro del proyecto.
- Conservar cambios de archivos mediante Local History.
- Recuperar versiones anteriores o archivos eliminados dentro del historial disponible.
- Consultar el historial de consultas ejecutadas.
- Acceder al registro SQL desde Help | Show SQL Log.
- Integrar sistemas de control de versiones como Git, SVN y Mercurial mediante los complementos correspondientes.
- Compartir scripts y archivos DDL mediante repositorios.

Local History recupera trabajo del editor; no restaura por sí solo cambios ya ejecutados en la base de datos.

Fuentes: [trabajo con archivos](https://lp.jetbrains.com/datagrip/working-with-files/), [historial y registro SQL](https://lp.jetbrains.com/datagrip/running-queries/), [archivos de consulta](https://www.jetbrains.com/help/datagrip/query-files.html) y [plugins](https://www.jetbrains.com/help/datagrip/managing-plugins.html).

## 25. Personalización, terminal y automatización

- Personalizar estilos de código, acciones, menús, barras y atajos.
- Ajustar paneles y ventanas de herramientas.
- Buscar acciones por su nombre.
- Utilizar una terminal dentro del IDE.
- Instalar, actualizar, habilitar y deshabilitar plugins.
- Instalar plugins desde Marketplace o archivos locales ZIP/JAR.
- Declarar plugins requeridos para un proyecto.
- Añadir integraciones y soporte adicional mediante plugins compatibles.
- Sincronizar categorías de ajustes entre instalaciones con Backup and Sync.
- Elegir si los ajustes se comparten solo entre instancias de DataGrip o entre IDE de JetBrains.
- Abrir proyectos y archivos desde la línea de comandos.
- Invocar comparación y combinación de archivos desde la CLI.
- Ejecutar funciones de formato e inspección desde la CLI.
- Instalar plugins desde la línea de comandos.
- Administrar conexiones y controladores por CLI en 2026.2.

Fuentes: [edición y personalización](https://www.jetbrains.com/help/datagrip/work-with-sql-code.html), [ventanas de herramientas](https://www.jetbrains.com/help/datagrip/tool-windows.html), [terminal](https://www.jetbrains.com/help/datagrip/terminal-emulator.html), [plugins](https://www.jetbrains.com/help/datagrip/managing-plugins.html), [sincronización](https://www.jetbrains.com/help/datagrip/sharing-your-ide-settings.html) y [CLI](https://www.jetbrains.com/help/datagrip/working-with-the-ide-features-from-command-line.html).

## 26. Novedades destacadas de 2026.2

Estas funciones aparecen expresamente en las notas oficiales de la versión consultada:

- Skills incorporadas para explorar bases, administrar conexiones y generar SQL.
- Herramientas MCP para crear y editar conexiones.
- Consentimiento para operaciones de bases de datos desde agentes en CLI.
- Historial de consultas que incluye las ejecutadas por agentes.
- Actualización de la introspección tras crear objetos mediante agentes.
- CLI de administración con comandos `dataSources list` y `dataSources manage`, procesamiento por lotes y JSON.
- Expresiones SQL en celdas y edición múltiple mediante ese modo.
- Modo de dos sesiones: una compartida y otra para introspección.
- Controladores incorporados para SQL Server, MongoDB, MySQL, PostgreSQL y Redis.
- Acceso al formato raw de planes junto a la representación en árbol.
- Selectores de rol y warehouse para Snowflake.
- Agrupación de objetos por prefijos en Database Explorer.
- Colores de conexiones y carpetas adaptados a los temas.
- Recorrido interactivo de aprendizaje y bases de demostración.

Fuente: [notas oficiales de DataGrip 2026.2](https://www.jetbrains.com/help/datagrip/release-notes-datagrip.html).

## 27. Límites importantes

- **Motor y dialecto:** que exista una conexión no significa que todas las funciones avanzadas estén soportadas. Consultar la clasificación y los rangos de versiones de cada motor.
- **Permisos:** explorar metadatos, modificar estructuras, escribir datos y depurar requiere los privilegios correspondientes en el servidor.
- **Transacciones:** `ROLLBACK` depende del motor y de la operación. No todas las modificaciones, especialmente DDL, son reversibles.
- **Solo lectura:** la protección del IDE debe complementarse con permisos adecuados en la base de datos cuando se necesita una restricción efectiva.
- **Comparaciones:** las diferencias dependen de los datos cargados y las opciones utilizadas.
- **Claves virtuales:** describen relaciones para el IDE; no hacen que el servidor valide los datos.
- **Esquemas DDL:** representan estructuras; no son una copia de los registros de la base de datos.
- **Respaldos:** los dumps integrados dependen de herramientas y motores concretos.
- **IA y complementos:** su disponibilidad y consumo dependen de la versión, el plugin, el proveedor y la cuenta o plan utilizado. Las propuestas de SQL necesitan revisión.
- **Cobertura del inventario:** se documentan las funciones identificadas en las fuentes consultadas; las acciones específicas de cada motor y el catálogo abierto de plugins amplían esa lista.

Referencias para comprobar disponibilidad: [fuentes de datos](https://www.jetbrains.com/help/datagrip/managing-data-sources.html), [documentación de DataGrip](https://www.jetbrains.com/help/datagrip/), [documentación de AI Assistant](https://www.jetbrains.com/help/ai-assistant/use-ai-with-databases.html) y [novedades del producto](https://www.jetbrains.com/datagrip/whatsnew/).
