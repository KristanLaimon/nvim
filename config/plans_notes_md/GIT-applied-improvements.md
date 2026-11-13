# [Enhance]: Discord Presence + Git center

I'd like custom presence msgs while in git center and related dashboards:

> Note: Id like to show this precense, without exposing innecesary private/sensitive info

While in git-center i like to show something like:

"Gitting around..."
"in <projectName>"

In Git Diff Mode Manager:

"Selecting how to review project..."
"in <projectName>"


In case I select:

1. Working Tree vs HEAD
"Reviewing Working Tree vs HEAD"
"in <projectName>"


2. Last N commits
"Reviewing last <number> commits"
"in <projectName>"


3. Until a branch
"Reviewing a whole branch..."
"in <projectName>"

If im in Log Diff then:
"Reviewing commit log..."
"in <projectName>"

----

# [Feat]: Discord Presence Opt-In projectname redacted
This is a config stored in ./foxnvim, probably a simple boolean.
Create a new command pallete, so I can opt-in to hide the project name
in my discord pressence, like this:

"<any message>"
"in <random_message>"

<random_message> will be similar to the messages shown when vibe-coding,
i mean, that array where i store a lot of words/phrases, this time will
be about places, real places, but fox puned 1/2, like:

The Backrooms, <Fortnite_Places>, "Foxaland", etc...., 

neutral/funny

well in reality is more like a "Censure" level, 

No Censure: Default level, current behavior
ProjectName Only: The level I described to you
Full: It won't show nor theproject name nor any filename, only showing the language icon 
as it normally does.

----

# [Enhance]: Improve the sidebar of git diff mode shortcuts/help area

 [J/K / ]c/[c]: Jump Diff
 [Enter/Space]: Select | [h/Esc]: Code
 [c]: Range | [e]: Export | [i]: Import
 [B]: Toggle Blame Author Column
 [s]: Classic / Before | After
 [q]: Back to Diff Mode Manager
 Annotations (in code panels):
 [c]: Add | [C]: Copy whole session
 [da]: Delete | [U]: Sessions
 [q/r]: Previous/Next annotation

Is like this, could be better like:

 [J/K / ]c/[c]: Jump Diff
 [Enter/Space]: Select | [h/Esc]: Code
 [c]: Range | [e]: Export | [i]: Import
 [B]: Toggle Blame Author Column
 [s]: Classic / Before | After
 [q]: Back to Diff Mode Manager

 Annotations (in code panels):
 [c]: Add | [C]: Copy whole session
 [da]: Delete | [U]: Sessions
 [q/r]: Previous/Next annotation

And make "B" and "s" available in tab/diff code as well, not only sidebar


