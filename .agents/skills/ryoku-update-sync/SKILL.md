---
name: ryoku-update-sync
description: Review Lua files added or changed by Ryoku updates in this FoxVim project, integrate useful improvements into the existing handmade configuration, and remove redundant Ryoku additions. Use when syncing or cleaning up Ryoku editor defaults after an update.
---

# Ryoku update sync

Preserve handmade FoxVim while learning from incoming Ryoku editor code. Usually
remove the incoming files after review; retain one only for a necessary
integration. The user's roughly 90% deletion expectation is a preference, not a
quota.

## Inspect

Read the project's AGENTS.md and the Ryoku vault's AGENTS.md and desktop.md at
`~/.local/share/ryoku/rashin/`. Follow the available ryoku skill for ownership and
desktop integration. Check `ryoku owner <path>` before modifications. Requested
cleanup authorizes removing reviewed additions in this project, not changing
packaged files or external Ryoku stores.

Start with `git status --short`, tracked diffs, and untracked file lists. Establish
Ryoku provenance from contents and available Git history or shipped baselines.
Untracked status or a name containing ryoku alone does not justify deletion.
Preserve unrelated work and user edits.

Read every candidate completely before removal. Past additions included
`lua/config/{lazy,options,keymaps,autocmds}.lua`,
`lua/plugins/{ryoku,ryoku-dashboard,99-ryoku-user}.lua`, and `.ryoku-lazyvim`.
These are discovery hints, never an automatic deletion list. Inspect other
incoming Lua files too.

## Compare and integrate

Trace startup from `init.lua` through `lua/vim_options.lua`, `lua/keymaps/`, and
`lua/lazy_init.lua`. FoxVim imports plugin directories explicitly; Ryoku's
alternative `config.lazy` bootstrap and top-level plugin specs may be inactive.
Search callers before removing files or changing imports.

Compare incoming behavior with the existing feature owners:

- `lua/plugins/fox/ui/ryoku_theme.lua`: palette translation, live refresh,
  opt-in sync, and Ex commands.
- `lua/plugins/fox/ui/theme_picker.lua` and `config/colors/ryoku-fox.lua`:
  selection and startup application.
- `lua/fox/core/environment.lua`: Ryoku detection.
- `lua/plugins/fox/ui/omarchy_theme.lua`: shared highlight construction used by
  the Ryoku adapter; preserve this dependency.
- `lua/fox/langs/<language>/init.lua`: language-specific settings and tools.

Extract concrete improvements such as changed palette paths or keys, better
fallbacks, or required integration behavior. Adapt them into the existing owning
module. Preserve user theme choices, cross-platform support, and minimal Lua-only
fresh installs. Register new actions in the existing command palette and Ex
commands. Do not adopt LazyVim, replace the dashboard, force a theme, or duplicate
bootstrap/keymaps merely because incoming files do so.

If existing behavior already covers the useful parts, make no speculative
integration changes. Retain an incoming module only when its purpose and loading
path are necessary; explain why it remains.

## Clean up and verify

Remove only reviewed redundant files, using explicit paths. Remove an associated
marker such as `.ryoku-lazyvim` only after reading it and checking its local
references and purpose. Do not recursively erase directories or remove FoxVim's
existing Ryoku support. Do not alter the updater to prevent future seeding unless
separately requested.

Run `nvim -l config/tests/syntax_check.lua` and relevant existing specs, e.g.
`nvim -l config/tests/run.lua ryoku_theme --only-failure`. For implementation changes, also run
applicable formatting/lint checks and tests; avoid repository-wide autoformatting
that alters unrelated work. Validate skill edits with the available skill-creator
validator.

Check final diff and status against the initial state. Report what was integrated
(or why nothing was needed), what was removed or retained, and verification
results. Do not claim cleanup prevents future Ryoku additions.
