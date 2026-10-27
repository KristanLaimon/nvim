1. When seeing table details:

│    ┌────────────────────────────────────┐                                                    ┌────────────────────────────────────┐ │
│    │ escolar.alumnos                    <───┐                                            ┌───┤ escolar.residencias_asesorias      │ │
│    │ PK FK Column                       │   │                                            │   │ PK FK Column                       │ │
│    │ PK    id                           │   │                                            │   │ PK    id                           │ │
│    │    FK carrera_id                   │   │                                            │   │    FK residencia_id                │ │
│    │    FK plan_estudio_id              │   │                                            │   │       fecha                        │ │
│    │    FK modulo_especialidad_id       │   │                                            │   │       actividad_asesoria           │ │
│    │    FK aspirante_id                 │   │                                            │   │       hora_asesoria                │ │
│    │    FK datos_facturacion_id         │   │                                            │   │       aceptado_asesor              │ │
│    │       control                      │   │                                            │   │       created_at                   │ │
│    │       nombre                       │   │                                            │   │       updated_at                   │ │
│    │       apellido_paterno             │   │                                            │   └────────────────────────────────────┘ │
│    │       apellido_materno             │   │                                            │                                          │
│    │       genero                       │   │                                            │                                          │
│    │       año_ingreso                  │   │                                            │   ┌────────────────────────────────────┐ │
│    │       periodo_ingreso              │   │                                            ├───┤ escolar.residencias_reportes       │ │
│    │       estatus                      │   │                                            │   │ PK FK Column                       │ │
│    │       password                     │   │                                            │   │ PK    id                           │ │
│    │       email                        │   │                                            │   │    FK residencia_id                │ │
│    │       año_inscripcion              │   │                                            │   │       reporte_pdf                  │ │
│    │       periodo_inscripcion          │   │                                            │   │       fecha                        │ │
│    │       fecha_titulacion             │   │                                            │   │       tipo_reporte                 │ │
│    │       fecha_egreso                 │   │                                            │   │       calificacion_externo         │ │
│    │       notificacion_correo          │   │                                            │   │       calificacion_interno         │ │
│    │       email_verified_at            │   │                                            │   │       created_at                   │ │
│    │       remember_token               │   │                                            │   │       updated_at                   │ │
│    │       created_at                   │   │                                            │   └────────────────────────────────────┘ │
│    │       updated_at                   │   │                                            │                                          │
│    └────────────────────────────────────┘   │                                            │                                          │
│                                             │                                            │                                          │



theres a "PK FK Column" everywhere. thats a bug.

2.
In table details: (same place as 1.)
I want it to have the same "enter" (caret table aware) funciontality as the same of
live mode, if my careta is in a table in that part, i want the b, enter and other shorcuts available for it!,
if using "enter" it would open another popup with table details on top of my alread existing, so when closing that, my focus would be back where I was
previous table, like a stack!




2. When opening a table details: (same place as 1.)

It could happen that, if my caret goes focusingg another part of my nvim editor, it won't close the table details popup,
and somtimes the "q" doesn´t work and doesnt close it. happens too much and i have to use the mouse to focus again there and close it....

## Implemented

- [x] Remove the repeated `PK FK Column` heading from relationship cards.
- [x] Make inspector actions use the table under the caret; Enter stacks another inspector and closing it returns to the previous view.
- [x] Dismiss the inspector stack when focus moves elsewhere; keep q/Esc closing reliable.
