Let's create: "AgenticMode.plan.md"

This will be the third mode new mode for foxnvim.

I currently have this idea for the new screen for this mode (like the whole screen dedicated for query mode),
should be toggleable with F4, F3 for query mode.

My design was like this:

┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┌───────────────────────────────┐─────────────────────────────────────┐
│ Agentic Mode                                                                                                │ Context/Skills Loaded         │ Files Changed                       │
│                                                                                                             │                               │                                     │
│                                                                                                             │                               │ file-1                              │
│                                                                                                             │   ------                      │ file-2                              │
│                                                                                                             │  ┌────────────┐               │ file-3                              │
│            <logolang> <fieName>                                                                             │  │            │               │                                     │
│            ┌─────────────────┐               ┌─────────────────┐        ┌────────────────────┐              │  │            │               │                                     │
│            │                 │               │                 │        │                    │              │  │            │               │                                     │
│            │                 │               │                 │        │                    │              │  │            │               │                                     │
│            │                 │               │                 │        │                    │              │  │            │               │                                     │
│            │                 │   calls────   │                 │        │                    │              │  └────────────┘               │                                     │
│            │                 ┼───────────────┼                 ┼────────┼                    │              │  Tokens: ##                   │                                     │
│            │                 │   ───calls    │                 │        │                    │              │                               │                                     │
│            │                 │               │                 │        │                    │              │             ┌─────────────┐   │                                     │
│            │                 │               │                 │        │                    │              │             │             │   │                                     │
│            │                 │               │                 │        │                    │              │             │             │   │                                     │
│            └────────┬────────┘               └─────────────────┘        └────────────────────┘              │             │             │   │                                     │
│            Tokens:  │                        Tokens:                    Tokens:                             │             │             │   │                                     │
│                     │                                                                                       │             │             │   │                                     │
│                     │                                                                                       │             └─────────────┘   │                                     │
│                     │                                                                                       │             Tokens: ##        │                                     │
│                     └──────────────┐                                                                        │                               │                                     │
│                                    │                                                                        │   ┌─────────────┐             │                                     │
│                                    │                                                                        │   │             │             │                                     │
│                                    │                                                                        │   │             │             │                                     │
│                           ┌────────┼─────────┐                                                              │   │             │             │                                     │
│                           │                  │                                                              │   │             │             │                                     │
│                           │                  │                                                              │   │             │             │                                     │
│                           │                  │                                                              │   └─────────────┘             │                                     │
│                           │                  │                                                              │   Tokens: ##                  │                                     │
│                           │                  │                                                              │                               │                                     │
│                           │                  │                                                              │                               │                                     │
│                           │                  │                                                              │                               │                                     │
│                           │                  │                                                              │                               │ Chat: <chat Name here>              │
│                           │                  │                                                              │                               │                                     │
│                           │                  │                                                              │                               │ Available Context: ###%/###%        │
│                           └──────────────────┘                                                              │                               │ Tokens Spent:                       │
│                                                                                                             │                               │                                     │
│                                                                                                             │                               │ Model: <*********.                  │
│                                                                                                             │                               │                                     │
│                                                                                                             │                               │                                     │
│                                                                                                             │                               │                                     │
│                                                                                                             │                               │                                     │
│                                                                                                             │                               │                                     │
│                                                                                                             │                               │                                     │
│ Subtotal:                                                                                                   │ Subtotal:                     │                                     │
│ Total (all):                                                                                                │                               │                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────└───────────────────────────────┘─────────────────────────────────────┘

it should recognize this from:

codex
claude
opencode
agy (gemini)

and other common AI cli tools as well (from terminal)

The "files" should appear on screen in real-time as the agents create-edits-them!
The same for the mode, availble context, tokens spent

and idk if possible but to see how many tokens are spent on files reading, and see if they've been read again (more tokens,accumulative, green color i guess)

deletions additions

i wantto be able to move through the "files" with vim motions, and when pressing "Enter" will show the git diff dashboard (with all the diff) (is the one
that shows files "before" and "after") with allfiles, but having the current selected file as the focused one ofcourse.

In case for the skills/context files read only (these are files that were only read, notmodified at all), they will simply open that file
in foxnvim (opening editor default mode to that file), but with the eception that i ll have an easy shortcut only available in this transition because im in Agentic-Editor mode (submode)

there are 2 submodes (Default, the actual I've described to you) dn "SubEditor" that is this one.
