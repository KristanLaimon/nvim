Implemented (2026-10-22):

- [x] Query-only bottom activity/status bar, full error copying, and Default/Visually indicator.
- [x] Connection entries above a separated shortcut footer.
- [x] Saved SQL browser below connections, Alt+h/l tab navigation, and empty-editor prompt.
- [x] Result details below the grid, Shift+h/l columns, Shift+j/k rows, and searchable popup selections.
- [x] Selected diagram columns first, 15-column default, and project-persistent C / :FoxQueryColumns setting.

Original requests:

1. From this query situation:


LIVE QUERY DIAGRAM
Diagram follows SQL at the cursor | cache 21:49

+--------------------------+       +--------------------------+
| PlayerKisses             --------> Player                   |
| PlayerKisses             |       | Player                   |
| *k  member_1             |       |  k  id                   |
|     member_2             |       |     username             |
| *   kisses_count         |       |     profilePicturePath   |
+--------------------------+       |     actualRank           |
                                   |     whatsappNickName     |
                                   |     whatsappid           |
                                   |     whatsappid_pn        |
                                   |     whatsappid_lid       |
                                   |     role                 |
                                   |     joined_date          |
                                   |     is_active            |
                                   | ... 3 more; Enter inspec |
                                   +--------------------------+

[PlayerKisses] -- INNER --> [Player]: Player.id = PlayerKisses.member_1
[Player] .... [LiveStreamSession] related, not joined
[Player] .... [Match_Player_TeamColor_Played] related, not joined
[Player] .... [PlayerSecondarynames] related, not joined
[Player] .... [Player_Player_Trust] related, not joined
[Player] .... [Player_Season_Plays] related, not joined
[Player] .... [Player_Titles] related, not joined
[Player] .... [TournamentMatch] related, not joined
[Player] .... [TournamentMatchup_Player_Played] related, not joined
[Player] .... [Tournament_Player_Subscriptions] related, not joined
Column markers: * selected | k JOIN | f filter | ? possible FK join | dim unused
In this diagram pane: move to a table, Enter inspect, J Insert JOIN; Ctrl+h returns to SQL


We need to create a bottom "Status Bar" exclusive for query mode. which will have left part (content aligned to the left)
and right part (content aligned to the right):

to the left will be the SQL status (if failed?) if failed, the whole sql error, with click it should copy the contents from it!,
for easy debugging and that stuff.

In default view it should be the status to the left:
ACTIVITY | Completed | 0.00s | SELECT * FROM "Tournament" ORDER BY "id" LIMIT 200 
for example

This content:
"Column markers: * selected | k JOIN | f filter | ? possible FK join | dim unused
In this diagram pane: move to a table, Enter inspect, J Insert JOIN; Ctrl+h returns to SQL"
is innecesary because, by pressing enter into a relation entry aka:  [Player] .... [TournamentMatch] related, not joined
it shows a popup with all the shortcuts there. So:
""Column markers: * selected | k JOIN | f filter | ? possible FK join | dim unused
In this diagram pane: move to a table, Enter inspect, J Insert JOIN; Ctrl+h returns to SQL"
" is pure noise.


2.

In connection sidebar:

CONNECTIONS
a Add  e Edit  d Delete
Enter Connect  D Disconnect

* KLDB

It should be first the list on top, then the info about  shortcuts in bottom of that sidebar panel!
a Add  e Edit  d Delete
Enter Connect  D Disconnect

And add ------ separator on bottom better format, is kinda lazy but works well.


3. When creating a sql, workign in it in query mode, then restarting, is ok for it to not open again (this is workspace feature job)
but, all created sql files where are they? how can I open them? (created in previous sessions), for that, create a bottom panel inside the
sidebar left in default mode, to see all the files, it should be easily selectable, like a mini neo-tree but for the sqls folder (i think is
stored in .foxnvim) in that folder. Of course, I should be able to open many of them, and easily change tabs the same way I do 
normally in code tabs (with alt + h or alt + l to move to left and right respectively), there should be a default message in the 
sql editor if I close all tabs, "Select a SQL tab or create a new one with <the shortcut>".



4. In results tabls, normally shows a result like this:

RESULTS | run #62 | KLDB | 22:00:52 | query-20261022-214913-1.sql
Enter: expand row | y: copy row | e: export | gR: follow foreign key
Result 1 | 2 loaded rows
+----+--------------------------------+----------------------------------+---------------+-----------+-----------------+---------+----------------+-----------------+-------------+--------------+--------+-------------------------+-------------------------+---------------+-----------------+-----------------+---------------+-----------------------+-----------+
| id | name                           | description                      | creationDate  | beginDate | matchPeriodTime | endDate | cover_img_name | tournament_type | max_players | match_format | status | custom_players_per_team | whatsapp_group_chat_id  | prize_pool    | assignment_type | games_per_round | min_kl_points | final_games_per_round | game_mode |
+----+--------------------------------+----------------------------------+---------------+-----------+-----------------+---------+----------------+-----------------+-------------+--------------+--------+-------------------------+-------------------------+---------------+-----------------+-----------------+---------------+-----------------------+-----------+
| 42 | ⭐ KL: 2ndo Aniversario (3vs3) | Han transcurrido dos años desde  | 1783521018311 | NULL      | 48              | NULL    | cover.png      | DE              | 24          | 3S           | 0      | 3                       | 120363410920712103@g.us | 1210-KLPOINTS | klpoints        | 3               | NULL          | 5                     | NM        |
| 43 | KL: 2ndo Aniversario (Lite)    | Versión chica del evento princip | 1784349328745 | NULL      | 48              | NULL    | cover.png      | DE              | 16          | 2S           | 0      | 2                       | 120363409430456880@g.us | 1230-KLPOINTS | klpoints        | 3               | NULL          | 5                     | NM        |
+----+--------------------------------+----------------------------------+---------------+-----------+-----------------+---------+----------------+-----------------+-------------+--------------+--------+-------------------------+-------------------------+---------------+-----------------+-----------------+---------------+-----------------------+-----------+



This info: 
RESULTS | run #62 | KLDB | 22:00:52 | query-20261022-214913-1.sql
Enter: expand row | y: copy row | e: export | gR: follow foreign key
Result 1 | 2 loaded rows
is annoying to be placed on top, it should be on bottom of that panel

And when focused my caret there, i should be able to move between columns with shift + h & shift + l  (left and right).
This is ok because i won't be writing anything there, its just a read-only panel the results panel.
and rows with shift +j and shift + k respectively.

There should be a [Default | Visually] status in status bar only when in query mode to know which submode im actuall at.

And, avoid menus in bottom with <number> selection, prefer popup menus selectables with telescope-like selection.

5. 

+--------------------------+       +--------------------------+
| PlayerKisses             --------> Player                   |
| PlayerKisses             |       | Player                   |
| *k  member_1             |       |  k  id                   |
|     member_2             |       |     username             |
| *   kisses_count         |       |     profilePicturePath   |
+--------------------------+       |     actualRank           |
                                   |     whatsappNickName     |
                                   |     whatsappid           |
                                   |     whatsappid_pn        |
                                   |     whatsappid_lid       |
                                   |     role                 |
                                   |     joined_date          |
                                   |     is_active            |
                                   | ... 3 more; Enter inspec |
                                   +--------------------------+



if i have selected with:

SELECT anotherProp FROM Player;

that prop is not being highlighted because its  in the ...3 more; Enter inspec

Selected that are hidden should be placed on top of table props, for visility. and

i dont like the ...3 more, hide when table has +15 columns only, and add a shorcut config in that screen to change this columns count view.

Persistent in proyect as well.
