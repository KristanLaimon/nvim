1. In Query Mode; 

In results panel, it shows:

+------+------------------------+
| id   | name                   |  (sticky heaer)
+------+------------------------+
| "BG" | "Grupo para bugs"      |
| "GE" | "General"              |
| "GF" | "General Full"         |
| "GV" | "Validador de Gc's"    |
| "R1" | "Rankeds 1S"           |
| "R2" | "Rankeds 2S"           |
| "TV" | "Validador de torneos" |
+------+------------------------+
Result 1 | 7 loaded rows

RESULTS | run #1 | KLDB | 16:11:19 | query-20261022-231253-1.sql
Enter: expand row | y: copy row | e: export | gR: follow foreign key

which is ok. But i dont want +--- style i want:

Example:
┌────────┬──────────────────┬──────────────┐
│ ID     │ Nombre           │ Estado       │
├────────┼──────────────────┼──────────────┤
│ 001    │ Ana López        │ Activo       │
│ 002    │ Carlos Ruiz      │ Pendiente    │
│ 003    │ Sofía Pérez      │ Inactivo     │
└────────┴──────────────────┴──────────────┘

with ┌ ┐ └ ┘ ─ │ ┬ ┴ ├ ┤ ┼  characters! for smoother table rendering


This should be the same for the dynamic submode of query mode. which uses this +- style as well:

+--------------------------+       +--------------------------+
| PlayerKisses             ----|---- Player                   |
| PlayerKisses             |   |   | Player                   |
| *   kisses_count         |   |   | *   username             |
|  k  member_1             |   |   |  k  id                   |
|     member_2             |   |   |     profilePicturePath   |
+--------------------------+   |   |     actualRank           |
                               |   |     whatsappNickName     |
                               |   |     whatsappid           |
                               |   |     whatsappid_pn        |
                               |   |     whatsappid_lid       |
                               |   |     role                 |
                               |   |     joined_date          |
                               |   |     is_active            |
                               |   |     preffered_language   |
                               |   |     PasswordHash         |
                               |   |     TokenVersion         |
                               |   +--------------------------+
                               |
                               |
+--------------------------+   |
| Player_titles            <----
| Player_titles            |
| *   title_id             |
|  k  player_id            |
+--------------------------+

...



