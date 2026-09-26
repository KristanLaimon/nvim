# 🐙 Secondary Git Repositories (Dotfiles Pattern)

[← Back to Wiki Index](index.md)

FoxVim provides built-in support for **secondary decoupled Git repositories** using the **Dotfiles pattern**.

This feature allows you to initialize and interact with a second (or multiple) independent Git repositories that share the same working directory (e.g. your project root or home directory) while keeping their `.git` history completely isolated in a bare repository directory (`git init --bare`).

---

## 🚀 Quick Start

### 1. Initialize a Secondary Repo
Run the following Ex command in Neovim:

```vim
:SecondaryGitInit foxgit ./git-fox git@github.com:your-user/private-repo.git
```

This automatically:
1. Creates the bare Git repository directory (e.g., `./git-fox` or `$HOME/.secrets-repo.git`).
2. Generates a dedicated **`.gitignore.foxgit`** file in your project root for this secondary repository.
3. Configures `core.excludesFile` to point to `.gitignore.foxgit` and sets `status.showUntrackedFiles no` (dotfiles standard).
4. Adds the optional remote URL `origin`.
5. Saves the repository configuration in `.foxnvim/secondary_repos.json`.
6. Generates `.foxnvim/secondary_aliases.sh` and `.foxnvim/secondary_aliases.ps1`.
7. Injects the shell functions/aliases (`foxgit`) directly into active Neovim terminal sessions (Git Bash, PowerShell, Zsh)!

### 2. Use in Neovim Terminal
Open Neovim's multi-terminal (`<C-;>` / `<A-1>`) and type:

```bash
foxgit status
foxgit add .gemini/ .foxnvim/ .env.local
foxgit commit -m "feat: updated private production config"
foxgit push -u origin main
```

---

## 🛡️ Dedicated `.gitignore.<alias>` & Bypassing Main `.gitignore`

### 1. Isolated `.gitignore.<alias>`
Each secondary repository uses its own dedicated ignore file **`.gitignore.<alias>`** (e.g., `.gitignore.foxgit`) located in your project root. 
- It is linked to the bare repo via `git config core.excludesFile ".gitignore.foxgit"`.
- It operates **completely independently** of the main repository's `.gitignore`. Anything listed inside `.gitignore.foxgit` (such as `node_modules/` or `.tmp/`) is ignored only by the secondary repository.

### 2. Automatic `-f` Force Add for Ignored Main Files
When adding files like `.gemini/`, `.foxnvim/`, or `.env.local` (which are usually ignored in the main project's `.gitignore`), `foxgit add` and `:SecondaryGit foxgit add` automatically pass `-f` (`git add -f`) under the hood. 

This ensures you can stage private or config files to your secondary repository without Git printing `.gitignore` error hints or blocking the add operation.

---

## 🐙 Git Control Center (`<C-S-g>`) & Telescope Switcher

Git Control Center integrates directly with secondary repositories:
- Secondary repositories appear as tabs (`🐙 foxgit`) in Git Control Center alongside the main root repository (`📦 root`) and submodules.
- **`:SecondaryGitSwitch` Command**:
  - If **only 1 secondary repository** exists: automatically defaults to it and switches Git Control Center focus directly!
  - If **more than 1 secondary repository** exists: launches an interactive **Telescope menu selector** to choose which secondary repo (or Main Root Repo) to activate!

---

## 🧰 Ex Commands & Palette Integration

| Ex Command | Description |
| :--- | :--- |
| `:SecondaryGit <alias> <git_subcommand...>` | Run any Git command on a secondary repo (e.g. `:SecondaryGit foxgit status`). |
| `:SecondaryGitInit [alias] [git_dir] [remote]` | Interactively initialize a new secondary bare repository. |
| `:SecondaryGitRename [old_alias] [new_alias]` | Rename a secondary repository alias. |
| `:SecondaryGitDelete [alias]` | Delete a secondary repository definition. |
| `:SecondaryGitSwitch` (or `:GitCenterSwitchSecondary`) | Switch active secondary repo in Git Center (Telescope selector if >1). |
| `:SecondaryGitManager` (or `:FoxSecondaryGit`) | Open interactive floating CRUD UI manager. |
| `:SecondaryGitSyncTerminal` | Re-sync and inject secondary repo shell aliases into open Neovim terminal buffers. |

All commands are accessible from the **Command Palette** (`<C-S-p>`).

---

## 📁 Configuration Format (`.foxnvim/secondary_repos.json`)

Configuration is stored per-project under `.foxnvim/secondary_repos.json`:

```json
{
  "version": 1,
  "repositories": [
    {
      "alias": "foxgit",
      "name": "foxgit",
      "git_dir": "./git-fox",
      "work_tree": ".",
      "show_untracked": false,
      "remote": "git@github.com:your-user/private-repo.git",
      "description": "Private project configs"
    }
  ]
}
```

---

## 🎛️ Interactive Manager UI (`:SecondaryGitManager`)

Inside the floating UI manager:
- `c` / `i` / `a`: **Create / Init** a new secondary repository.
- `r`: **Rename** secondary repository alias.
- `u`: **Edit / Update** secondary repo fields (`git_dir`, `remote`, `description`).
- `d` / `x`: **Delete** secondary repository definition.
- `w`: **Switch** active secondary repository in Git Control Center / Telescope.
- `s`: View `git status` of the highlighted secondary repository.
- `p`: Execute `git push` on the highlighted secondary repository.
- `l`: View `git log` history of the highlighted secondary repository.
- `t`: Re-inject shell aliases to open terminal windows.
- `e`: Edit `.foxnvim/secondary_repos.json` directly.
- `q` / `<Esc>`: Close manager window.
