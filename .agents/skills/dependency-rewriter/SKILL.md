---
name: dependency-rewriter
description: Resume FoxVim's dependency replacement plan, implementing and testing local plugin replacements sequentially with one commit per completed replacement. Use when asked to continue dependency rewrites or when invoked as $dependency-rewriter.
---

# Dependency rewriter

Resume `config/plans_notes_md/DEPENDENCYFOX.plan.md`. Read the project AGENTS.md,
that plan, `config/plans_notes_md/PLUGINS-LIST.md`, and Git status/history first.
Determine the next pending replacement from actual code and completed commits;
never restart completed work just because an older plan entry is stale.
Select pending items only from the implementation table. Plugins listed under
`Vital-Exceptions` are retained dependencies: skip them and do not move them back
into the rewrite queue unless the user explicitly requests it.

A bare invocation authorizes continuing the next pending replacement. If the
user specifies a count, finish that many replacements sequentially. For a bare
invocation complete one replacement, commit it, and report the next item.

For each plugin, before moving to the next:

1. Inspect its spec, installed implementation when available, all local consumers,
   commands, saved data, and transitive dependencies. Preserve the behavior
   FoxVim uses, including cancellation, errors, platform behavior and persistence.
2. Implement the necessary functionality in this repo using native Neovim APIs
   and existing FOX libraries. Do not relabel or vendor upstream code and call
   that a rewrite. Preserve licenses and attribution for any reused resources.
   Follow per-language ownership, minimal fresh installs, and command palette
   conventions in AGENTS.md.
3. Migrate consumers and remove external declarations and lockfile entries only
   once the local replacement actually supplies their used behavior. Do not
   delete installed plugin directories. Check transitive consumers before
   removing shared dependencies.
4. Test observable behavior with focused tests and relevant real editor/LSP/parser
   integration checks. Cover the plan's specific requirements and meaningful
   failure paths. Use `--only-failure` by default for full and filtered Lua test
   runs (e.g. `nvim -l config/tests/run.lua tasks --only-failure`); inspect failed
   cases and totals without filling context with passing cases. Run syntax and applicable formatting/lint checks. Fix failures
   before treating the rewrite as complete; do not mark an unverified substitute
   complete just to meet the requested count.
5. Update the dependency plan's status, completion notes and next item, and the
   plugin inventory/counts. Update affected user documentation.
6. Review the diff and stage only files for this replacement. Create a normal
   commit after successful tests. No push, force operations, history rewriting,
   or assistant co-author trailer. Preserve unrelated uncommitted user work.
   Then proceed to the next requested plugin.

Separate setup changes or skill changes into their own tested/reviewed commits.
When a concrete blocker prevents safe completion, leave accurate progress notes
in the plan, report the failing check, and do not commit the plugin as finished.
Do not install heavy optional language bundles simply to run tests.

Report the completed replacements, validation, commit hashes and next pending
item. Never claim tests or integrations were exercised when they were not.
