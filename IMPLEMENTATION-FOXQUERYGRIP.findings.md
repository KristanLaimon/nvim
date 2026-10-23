
1. Ctrl + alt + 0 its not a good shortcut to change between modes. I want a fast shortcut as well,
that instead of a menu to select form directly will cycle between modes (currently only edit and query mode available of course)

2. I'ts not intuitive the default view of query mode:

- While typing the query is not being executed below!...

SELECT Match.date_played_id FROM Match; -- this is ok! great
SELECT date_played_id FROM Match;  --for some reason i dont have intelissense if only using the column name..


3. ctrl + <vimmotions like  hjkl> all work except ctrl + k , that opens the file finder!, its should not be usable from query mode.


4. The Inspect Table is ugly as hell:

RegisteredWhatsappGroups
Entity | 1 outgoing / 0 incoming FK(s)

STRUCTURE
PK chat_id  TEXT NOT NULL
   group_name  TEXT NOT NULL
   date_registered  BIGINT NOT NULL
   group_type  TEXT NOT NULL

INDEXES / UNIQUE KEYS
RegisteredWhatsappGroups_date_registered_key UNIQUE
RegisteredWhatsappGroups_chat_id_key UNIQUE
sqlite_autoindex_RegisteredWhatsappGroups_1 UNIQUE

RELATIONSHIPS (visible metadata only)
RegisteredWhatsappGroups -- child FK -> referenced key -- RegisteredWhatsappGroupType
  group_type = id
 
==========================

literally in the popup, it should have the UML table format

┌────────────────────────────────────┐                       
│            table name here         │                       
│                                    │                       
┼────────────────────────────────────┤                       
│ columns .... FK PK NN              │                       
│                                    │        NN for NOT NULL
│                                    │                       
│                                    │                       
│                                    │                       
├────────────────────────────────────┤                       
│ other section                      │                       
│                                    │                       
│                                    │                       
│                                    │                       
│                                    │                       
│                                    │                       
└────────────────────────────────────┘

idk like this in popup 


5. There are no instructions or help line msgs in corners or per section to know how to use this for example
about adding new connection, changing between "submodes" of query mode, and that, its like almost blank
and it assumes I know all by memory. Contra intuitive.
