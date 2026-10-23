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

This popup menu is too small, it should occupy dynamic height and view de tal manera que, every entry-prop-row
should be in one row, because if too large prop names, then the rest of textof each line wraps to the next line and looks ugly.


.2

Forsome reason after "enter" a table, this info is being shown in popup (which is good!):
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
The section RELATIONSHIPS is very ugly,current result/implementation: 



+-------------------------------------------------------------------------------------------+       +-------------------------------------------------------------------------------------------+
| > Player                                                                                  <-------- LiveStreamSession                                                                         |
| PK FK Column                                                                              |       | PK FK Column                                                                              |
| PK    id                                                                                  |       | PK    id                                                                                  |
|       username                                                                            |       |    FK TournamentMatchupId                                                                 |
|       profilePicturePath                                                                  |       |    FK StartedByPlayerId                                                                   |
|       actualRank                                                                          |       |       StreamPath                                                                          |
|       whatsappNickName                                                                    |       |       StreamType                                                                          |
|       whatsappid                                                                          |       |       Title                                                                               |
|       whatsappid_pn                                                                       |       |       Description                                                                         |
|       whatsappid_lid                                                                      |       |       IsActive                                                                            |
|       role                                                                                |       |       StartedAt                                                                           |
|       joined_date                                                                         |       |       EndedAt                                                                             |
|       is_active                                                                           |       +-------------------------------------------------------------------------------------------+
|       preffered_language                                                                  |
|       PasswordHash                                                                        |
|       TokenVersion                                                                        |
+-------------------------------------------------------------------------------------------+


+-------------------------------------------------------------------------------------------+       +-------------------------------------------------------------------------------------------+
| Match_Player_TeamColor_Played                                                             |       | PlayerKisses                                                                              |
| PK FK Column                                                                              |       | PK FK Column                                                                              |
| PK FK match_played_date_id                                                                |       | PK FK member_1                                                                            |
| PK FK player_id                                                                           |       | PK FK member_2                                                                            |
|    FK teamColorId                                                                         |       |       kisses_count                                                                        |
|       is_winner                                                                           |       +-------------------------------------------------------------------------------------------+
+-------------------------------------------------------------------------------------------+


+-------------------------------------------------------------------------------------------+       +-------------------------------------------------------------------------------------------+
| PlayerSecondarynames                                                                      |       | Player_Player_Trust                                                                       |
| PK FK Column                                                                              |       | PK FK Column                                                                              |
| PK FK player_id                                                                           |       | PK FK who_trust_player_id                                                                 |
| PK    username                                                                            |       | PK FK trusted_player_id                                                                   |
+-------------------------------------------------------------------------------------------+       |    FK match_format_id                                                                     |
                                                                                                    +-------------------------------------------------------------------------------------------+


+-------------------------------------------------------------------------------------------+       +-------------------------------------------------------------------------------------------+
| Player_Season_Plays                                                                       |       | Player_Titles                                                                             |
| PK FK Column                                                                              |       | PK FK Column                                                                              |
| PK FK season_id                                                                           |       | PK FK player_id                                                                           |
| PK FK player_id                                                                           |       | PK FK title_id                                                                            |
|       score_1s                                                                            |       +-------------------------------------------------------------------------------------------+
|       score_2s                                                                            |
|       score_3s                                                                            |
|       score_HS                                                                            |
|       score_VL                                                                            |
|       score_BK                                                                            |
+-------------------------------------------------------------------------------------------+


Which, obviously there are many other tables that have connection through FK to my main focus table that actually is "Player",
and of course my table Player or main could have connection outbounds to another, those relationship aren't being shown with
arrows or connections: 

id like to have the main focus table in center of diagram:

                                  responsive design!                                                             
                                                                                                                 
                                                                                                                 
                                      for wide screns                                                            
                                                                                                                 
                                                                                                                 
                                     ────                                                                        
                                         ┌────────────────────────────────────────────────┐                      
                                         │                                                │                      
         ┌──────────────────────┐        │                                                │                      
         │                      │        │                                                │                      
         │                      │        │                                                │                      
         │                      │        │                                                │                      
         │                      │        └──────────────┬─────────────────────────────────┘                      
         │                      │                       │                                                        
         │                      ││                      │         ┌─────────────────────────────────────────────┐
         │                      ││                      │         │                                             │
         └──────────────────────┘│                      │         │                                             │
                                 │     ┌────────────────┴──┐      │                                             │
                                 │     │    main table     │      │                                             │
                                 └─────┼                   ┼──────┤                                             │
┌───────────────────────────┐          │                   │      │                                             │
│                           │          │                   │      └─────────────────────────────────────────────┘
│                           │          │                   │                                                     
│                           │          │                   │                                                     
│                           ┼───────┐  │                   │                                                     
│                           │       │ ─┼                   │                                                     
│                           │          │                   │                                                     
│                           │         ┌┴───────────────────┤        ┌────────────────────────────────────┐       
└───────────────────────────┘         │                    │        │                                    │       
                                      │                    │        │                                    │       
                                      │                    │        │                                    │       
                      ┌───────────────┼────────────────┐   └─────── │                                    │       
                      │                                │            │                                    │       
                      │                                │            │                                    │       
                      │                                │            └────────────────────────────────────┘       
                      │                                │                                                         
                      │                                │                                                         
                      │                                │                                                         
                      │                                │                                                         
                      └────────────────────────────────┘                                                         
                                                                                                                 
                                      in case of vertical                                                        
                   ┌─────────┐                                 ┌─────────────────┐                               
                   │         │                                 │                 │                               
                   │         │                                 │                 │                               
                   │         │                                 │                 │                               
                   │         │                         ┌───────┼                 │                               
                   │         │                         │       │                 │                               
                   │         │                         │       │                 │                               
                   └─────────┤                         │       │                 │                               
                             │          ┌──────────────┼──┐    └─────────────────┘                               
                             │          │    main table   │                                                      
                             └──────────┼                 │                                                      
                                        │                 │                                                      
                                        │                 │                                                      
                                        │                 │                                                      
                                        │                 │                                                      
                                        │                 │                                                      
                                        │                 │                                                      
                                        │                 │                                                      
                                        └──────┬──────────┘                                                      
                                               │                                                                 
                                               │                                                                 
                                               │                                                                 
                     ┌──────────────┐          │                                                                 
                     │              │          │                                                                 
                     │              │          │                                                                 
                     │              │          │                                                                 
                     │              ┼──────────┤                                                                 
                     │              │          │                                                                 
                     │              │          │      ┌───────────────┐                                          
                     │              │          │      │               │                                          
                     │              │          │      │               │                                          
                     │              │          ├──────┤               │                                          
                     └──────────────┘          │      │               │                                          
                                               │      │               │                                          
                                               │      │               │                                          
                                               │      │               │                                          
                                               │      │               │                                          
                                               │      │               │                                          
                                               │      └───────────────┘                                          
                                               │                                                                 
                                               └──────┐                                                          
                                                      │                                                          
                                                      │                                                          
                                ┌────────────────┐    │                                                          
                                │                │    │                                                          
                                │                │    │   ┌───────────┐                                          
                                │                │    │   │           │                                          
                                │                │    │   │           │                                          
                                │                ├────┼───┤           │                                          
                                │                │    │   │           │                                          
                                │                │    │   │           │                                          
                                │                │    │   │           │                                          
                                │                │    │   │           │                                          
                                └────────────────┘    │   │           │                                          
                                                      │   │           │                                          
                                                      │   └───────────┘                                          
                                                      │                                                          
                                                      │                                                          
                                                      │                                                          
                          ┌──────────────┐            │                                                          
                          │              │            │                                                          
                          │              │            │                                                          
                          │              ┼────────────┘                                                          
                          │              │                                                                       
                          │    other table idk          │                                                                       
                          │              │                                                                       
                          │              │                                                                       
                          │              │                                                                       
                          └──────────────┘



And, add colors to each part of this view, colors for the headers:
COLUMNS  |  PK primary / FK foreign / NN not null

and dimmed color version for the entries (the props of that tables),

the same for the other sections as "INDEXES / UNIQUE KEYS"

and relationships.



3. The environment feature + query mode are kinda bugged, when changing and coming back
to the environment with query mode opened, thewhole interface starts to fall apart, se desacomoda
en varias partes o hasta el panel de resultados se esconde/cierra. Además de que a veces como que se 
abre el neo-tree, lo cual está raro. Hazlo bien, compatible.

3.1
Something related to environments:

Let's say im on:

Environment 1:
nvim/

Environment 2:
proyect-work/

im on 1 which have neo-tree opened, then switch  to 2, then come back to 1, but my focus is always in neot-ree, instead of the last window I was in!

Bug

4. The feature for query mode that highlights the current query selected inside a square, its kinda annoying, better
lets make it be encerrado by just the top and bottom edges like this:

--------------------------------- (straigt line ascii,idk how to write it here foryou but you understand)
SELECT 
  username AS Username, 
  SUM(kisses_count) AS Total_Kisses,
  COUNT(Player_titles.title_id) AS Total_Titles
  FROM PlayerKisses
INNER JOIN Player ON Player.id = PlayerKisses.member_1
INNER JOIN Player_titles ON Player_titles.player_id = Player.id
GROUP BY Player.username
ORDER BY Total_Kisses DESC;
---------------------------------  (line)

of course the line will have the current-theme accentcolor.

---

2. In:
SQL FILES
  query-20261022-195047-1.sql
  query-20261022-214913-1.sql
  query-20261022-231253-1.sql

Should be using neo-tree, its kindahand made but id love it to be using neo-tree with the sql icons thanks to my font.


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


Move the:
DATABASE EXPLORER
/: filter  Enter: inspect  b: browse  n: notes
Filter: 

to Bottom, and make it more like 

------
DATABASE EXPLORER
/: filter Enter: inspect  b: browse  n: notes
Filter: 

With a separator line.


