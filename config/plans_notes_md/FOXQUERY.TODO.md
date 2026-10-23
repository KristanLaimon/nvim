1. In Query Mode; 

In results panel, it shows:

+------+------------------------+
| id   | name                   | (headers sticky, ok, keepthis)
----------------------------------
+------+------------------------+
| id   | name                   |  (headers duplicated, content panel, not neccesary)
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

which is ok except that the headers are being duplicated!, do not show the second,the duplicated ones.



2. In query Mode, when inspecting a table popup:
Normally shows this:

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ RegisteredWhatsappGroups                                                            │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ COLUMNS  |  PK primary / FK foreign / NN not null                                   │
│ NAME             TYPE    PK  FK  NN                                                 │
│ chat_id          TEXT    PK      NN                                                 │
│ group_name       TEXT            NN                                                 │
│ date_registered  BIGINT          NN                                                 │
│ group_type       TEXT        FK  NN                                                 │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ INDEXES / UNIQUE KEYS                                                               │
│ RegisteredWhatsappGroups_date_registered_key UNIQUE                                 │
│ RegisteredWhatsappGroups_chat_id_key UNIQUE                                         │
│ sqlite_autoindex_RegisteredWhatsappGroups_1 UNIQUE                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
.... more content


which is amazing job you did but.

"COLUMNS  |  PK primary / FK foreign / NN not null" should be aligned to right, because its justmetadata abouthow to read, remove "COLUMNS",
its like a dictionary/mini one-liner nomenclature section.

This section should not be dimmed:
NAME             TYPE    PK  FK  NN 



but the types: TYPE, TEXT
including: PK FK NN

should have their own color meaning!, 


The same for keywords like "UNIQUE" here: " RegisteredWhatsappGroups_date_registered_key UNIQUE "

all its only dimmed, one single color, which is difficult to read if everything is dimmed!....





