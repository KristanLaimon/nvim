# Fox Reader fixture project

Reusable files for Fox Reader's browser integration checks. The tests copy this
directory into a temporary workspace before editing or running its contents.

- `start.md`, `editable.md`, `html.md`, `outline.md` and `nested/` exercise
  Markdown, frontmatter, links, images, lists, tables and outline navigation.
- `data.json`, `bad.json` and `lines.txt` cover formatted JSON, invalid JSON and
  plain-text line breaks. `bad.json` is intentionally invalid.
- `hello.*`, `input.*`, `fail.js` and `wait.js` cover script output, interactive
  input, failures and stopping a running process. `fail.js` intentionally exits
  with an error; `wait.js` runs until stopped.
- `blocked.md`, `ordinary.md` and `notes.custom` support buffer conflict,
  non-frontmatter and configurable-extension checks.
