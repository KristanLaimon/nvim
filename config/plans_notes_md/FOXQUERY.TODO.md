Completed:

- [x] JOIN choices show column mappings, use table-based aliases, and simplify SQLite quoting safely.
- [x] Inspectors no longer duplicate their contents in the explorer.
- [x] SQL tree supports files/folders, create, rename, and confirmed delete, including open-buffer handling.
- [x] SQL files appear above connections in the default dashboard.
- [x] Native search in explorer/diagram/relationships; relationship popup preserves pane heights.

Original requests:

1.
Here:
+--------------------------+
| Player                   |
| Player                   |
| *   id                   |
| *   username             |
| *   profilePicturePath   |
| *   actualRank           |
| *   whatsappNickName     |
| *   whatsappid           |
| *   whatsappid_pn        |
| *   whatsappid_lid       |
| *   role                 |
| *   joined_date          |
| *   is_active            |
| *   preffered_language   |
| *   PasswordHash         |
| *   TokenVersion         |
+--------------------------+

[Player] .... [LiveStreamSession] related, not joined
[Player] .... [Match_Player_TeamColor_Played] related, not joined
[Player] .... [PlayerKisses] related, not joined
[Player] .... [PlayerSecondarynames] related, not joined
[Player] .... [Player_Player_Trust] related, not joined
[Player] .... [Player_Season_Plays] related, not joined
[Player] .... [Player_Titles] related, not joined
[Player] .... [TournamentMatch] related, not joined
[Player] .... [TournamentMatchup_Player_Played] related, not joined
[Player] .... [Tournament_Player_Subscriptions] related, not joined


When selecting with "enter" into an option:

[Player] .... [Player_Player_Trust] related, not joined

Opens up:

┌────────────────────────────────────────────────────────────────────────────────────────┐
│ Match                                                                                  │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ COLUMNS  |  PK primary / FK foreign / NN not null                                      │
│ NAME               TYPE     PK  FK  NN                                                 │
│ match_type         TEXT         FK  NN                                                 │
│ date_played_id     BIGINT   PK      NN                                                 │
│ blue_scoreboard    INTEGER          NN                                                 │
│ orange_scoreboard  INTEGER          NN                                                 │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ INDEXES / UNIQUE KEYS                                                                  │
│ sqlite_autoindex_Match_1 UNIQUE                                                        │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ RELATIONSHIPS (visible metadata only)                                                  │
│ Entity | 1 outgoing / 2 incoming FK(s)                                                 │
│ Match -> MatchType                                                                     │
│   match_type = id                                                                      │
│ Match_Player_TeamColor_Played -> Match                                                 │
│   match_played_date_id = date_played_id                                                │
│ TournamentMatch -> Match                                                               │
│   match_played_date_id = date_played_id                                                │
└────────────────────────────────────────────────────────────────────────────────────────┘

theres a detail when prssing J:

The workflow is awful:

Lets say we have this query:

SELECT * 
FROM PlayerKisses;

then these options:

LIVE QUERY DIAGRAM
Diagram follows SQL at the cursor | cache 23:24

+--------------------------+
| PlayerKisses             |
| PlayerKisses             |
| *   member_1             |
| *   member_2             |
| *   kisses_count         |
+--------------------------+

[PlayerKisses] .... [Player] related, not joined

i press enter in:

[PlayerKisses] .... [Player] related, not joined


then opens up this:

...
PlayerKisses -> Player (PlayerKisses:1)
> PlayerKisses -> Player (PlayerKisses: 0)

2
Choose foreign key mapping
>
...

Wtf are these options? 1 and 0? wtf (project: /c/Users/USER/VMS SHARED/SoftwareDevelopment/KL_ALL_IN_ONE_MAIN/src_data/kldb.db)

then asks for an "alias" by default t3, which is horrible it should suggest based in initials of table (player -> p) if already existing table
that starts with p in query, then (player -> p2) and so on, and better sintaxis, without many "" in the final output




1.2

Forsome reason after "enter" a table, then its info is copied in bottom panel sidebar right in default view:
┌────────────────────────────────────────────────────────────────────────────┐
│ Match                                                                      │
├────────────────────────────────────────────────────────────────────────────┤
│ COLUMNS  |  PK primary / FK foreign / NN not null                          │
│ NAME               TYPE     PK  FK  NN                                     │
│ match_type         TEXT         FK  NN                                     │
│ date_played_id     BIGINT   PK      NN                                     │
│ blue_scoreboard    INTEGER          NN                                     │
│ orange_scoreboard  INTEGER          NN                                     │
├────────────────────────────────────────────────────────────────────────────┤
│ INDEXES / UNIQUE KEYS                                                      │
│ sqlite_autoindex_Match_1 UNIQUE                                            │
├────────────────────────────────────────────────────────────────────────────┤
│ RELATIONSHIPS (visible metadata only)                                      │
│ Entity | 1 outgoing / 2 incoming FK(s)                                     │
│ Match -> MatchType                                                         │
│   match_type = id                                                          │
│ Match_Player_TeamColor_Played -> Match                                     │
│   match_played_date_id = date_played_id                                    │
│ TournamentMatch -> Match                                                   │
│   match_played_date_id = date_played_id                                    │
└────────────────────────────────────────────────────────────────────────────┘
it should not be there!...



---

2. In:
SQL FILES
  query-20261022-195047-1.sql
  query-20261022-214913-1.sql
  query-20261022-231253-1.sql

its not like a neo-tree, i cant delete, rename, or create with "a" or even folders with "A".


3. Swap connections and files sql sections please (of place only in dashboard)



4. In:

DATABASE EXPLORER
/: filter  Enter: inspect  b: browse  n: notes
Filter: 

  LiveStreamSession
> Match
  MatchType
  Match_Player_TeamColor_Played
  MetadataUpdates
  Player
  PlayerKisses
  PlayerSecondarynames [note]
  Player_Player_Trust
  Player_Season_Plays
  Player_Titles
  Rank
  RegisteredWhatsappGroupType
  RegisteredWhatsappGroups
  Role
  Season
  TeamColor
  Titles
  Tournament
  TournamentMatch
  TournamentMatchup
  TournamentMatchup_Player_Played
  TournamentRound
  TournamentType
  Tournament_Player_Subscriptions
  Tournament_Rank_RanksAdmitted
  __drizzle_migrations

 the / should be the default / behavior of nvim, remove the / behavior there, is strange, the same for the relationship panel when 
opening relationship panel.

And, height bug, when opening relationship panel, then closing it with q, the original bottom panel keeps that height, it should be restored.

