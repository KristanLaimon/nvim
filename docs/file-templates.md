# File creation templates

FoxVim offers a template menu when you open a new, empty file and its Neovim filetype has at least one Markdown template. It also works for files created through the file explorers. Press Enter to insert a template, or Escape to leave the file empty. Run `:FoxFileTemplate` to reopen the menu while the buffer is empty. The command is also in the Command Palette.

Add a file under `templates/<filetype>/` in the Neovim config directory. The folder name is the Neovim filetype, such as `cs`, `lua`, `svelte`, or `typescriptreact`. A new Markdown file becomes a menu choice without changing Lua code. Templates in the current workspace's `.foxnvim/templates/<filetype>/` or `templates/<filetype>/` are also read, with workspace choices taking precedence over config choices of the same name.

For example, `templates/cs/class.md`:

```md
---
name: Class
description: Standard C# class
index: 0
---
namespace <%csharp_namespace%>;

internal class <%filename%>
{
    $0
}
```

`name`, `description`, and `index` set the label, description, and sort order. The text after the closing `---` is inserted into the new file. `$0` sets the cursor position. Common placeholders include `<%filename%>` (name without extension), `<%filename_ext%>`, `<%classname%>`, `<%filetype%>`, `<%date%>`, `<%year%>`, and `<%author%>`. C# also supplies `<%csharp_namespace%>` and `<%csharp_identifier%>`. An unavailable namespace removes a standalone `namespace <%csharp_namespace%>;` line.

Use `$1`, `$2`, `$3`, and so on for editable fields. Tab moves to the next number, Shift-Tab moves back, and `$0` is the final cursor position. Repeated uses of the same number stay in sync: `${1:Name}` and another `$1` both show `Name` until you edit either one. Use `$0` once per template.

The C# namespace comes from the nearest ancestor `.csproj` (`RootNamespace` or the project name), then adds the file's folder path. Without a project, a nearby `Program.cs` or other C# file with a namespace can supply the base namespace. Templates never replace a file after you type in its buffer while the menu is open.
