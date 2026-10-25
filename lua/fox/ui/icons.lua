-- FOX icon catalog. Glyph choices use the Nerd Font installed by the user.
-- This catalog is authored here; no upstream plugin data is vendored.
local M = {}
local catalog = { file = {}, extension = {}, filetype = {}, directory = {}, os = {} }
local palette = {
	Azure = "#3a8bfd",
	Blue = "#4e79f0",
	Cyan = "#22d3ee",
	Green = "#6cc644",
	Grey = "#8c8c8c",
	Orange = "#f38019",
	Purple = "#a855f7",
	Red = "#f14c4c",
	Yellow = "#f1e05a",
}
local defaults = {
	file = { glyph = "󰈙", hl = "MiniIconsGrey" },
	directory = { glyph = "󰉋", hl = "MiniIconsBlue" },
	os = { glyph = "", hl = "MiniIconsGrey" },
}
local function add(names, glyph, color)
	for name in names:gmatch("%S+") do
		catalog.filetype[name] = { glyph = glyph, hl = "MiniIcons" .. color }
	end
end
add("lua", "󰢱", "Blue")
add("javascript javascriptreact", "󰌞", "Yellow")
add("typescript typescriptreact", "󰛦", "Azure")
add("php blade", "󰌟", "Purple")
add("python", "󰌠", "Yellow")
add("go", "󰟓", "Cyan")
add("rust", "󱘗", "Orange")
add("c cpp", "󰙱", "Blue")
add("cs", "󰌛", "Purple")
add("ruby", "󰴭", "Red")
add("haskell", "󰲒", "Purple")
add("zig", "", "Orange")
add("sh bash zsh fish powershell", "", "Green")
add("html xml", "󰌝", "Orange")
add("css scss sass less", "󰌜", "Blue")
add("svelte", "", "Orange")
add("vue", "󰡄", "Green")
add("astro", "", "Orange")
add("json jsonc yaml toml dosini", "", "Yellow")
add("markdown text rst vimdoc", "󰍔", "Grey")
add("vim query", "", "Green")
add("dockerfile", "󰡨", "Azure")
add("sql", "", "Yellow")
add("git gitcommit gitignore diff", "", "Red")
add("make cmake", "", "Orange")
add("teal", "󰢱", "Cyan")
add("foxnvim", "🦊", "Orange")
add("proto", "", "Azure")
local aliases = {
	js = "javascript",
	jsx = "javascriptreact",
	ts = "typescript",
	tsx = "typescriptreact",
	py = "python",
	rs = "rust",
	rb = "ruby",
	hs = "haskell",
	h = "c",
	hpp = "cpp",
	cc = "cpp",
	cxx = "cpp",
	ps1 = "powershell",
	md = "markdown",
	yml = "yaml",
	tl = "teal",
	txt = "text",
	["blade.php"] = "blade",
}
for name, item in pairs(catalog.filetype) do
	catalog.extension[name] = vim.deepcopy(item)
end
for ext, ft in pairs(aliases) do
	catalog.extension[ext] = vim.deepcopy(catalog.filetype[ft])
end
for name, ft in pairs({
	Dockerfile = "dockerfile",
	Makefile = "make",
	[".gitignore"] = "gitignore",
	[".gitconfig"] = "git",
	[".env"] = "dosini",
	["LICENSE"] = "text",
	["package.json"] = "json",
	["Cargo.toml"] = "rust",
}) do
	catalog.file[name] = vim.deepcopy(catalog.filetype[ft])
end
for _, name in ipairs({ "linux", "windows", "macos", "darwin" }) do
	catalog.os[name] = { glyph = name == "linux" and "" or name == "windows" and "" or "", hl = "MiniIconsBlue" }
end
local function highlights()
	for name, color in pairs(palette) do
		vim.api.nvim_set_hl(0, "MiniIcons" .. name, { fg = color })
	end
end
function M.setup(opts)
	for category, entries in pairs(opts or {}) do
		if catalog[category] then
			for name, item in pairs(entries) do
				catalog[category][name] = vim.tbl_extend("force", catalog[category][name] or defaults.file, item)
			end
		end
	end
	highlights()
	_G.MiniIcons = M
end
function M.get(category, name)
	name = type(name) == "string" and name or ""
	if category == "default" then
		local item = defaults[name] or defaults.file
		return item.glyph, item.hl, true
	end
	local entries = catalog[category] or {}
	if category == "file" or category == "directory" then
		name = name:gsub("\\", "/"):match("([^/]+)/*$") or name
	end
	local item = entries[name] or entries[name:lower()]
	if not item and category == "file" then
		local suffix = name
		while suffix:find("%.") do
			suffix = suffix:match("%.(.*)")
			item = catalog.extension[suffix:lower()]
			if item then
				break
			end
		end
		if not item then
			local ft = vim.filetype.match({ filename = name })
			item = ft and catalog.filetype[ft]
		end
	end
	local fallback = item == nil
	item = item or defaults[category] or defaults.file
	return item.glyph, item.hl, fallback
end
function M.list(category)
	return vim.tbl_keys(catalog[category] or {})
end
M.setup({})
vim.api.nvim_create_autocmd(
	"ColorScheme",
	{ group = vim.api.nvim_create_augroup("fox_icons_palette", { clear = true }), callback = highlights }
)
return M
