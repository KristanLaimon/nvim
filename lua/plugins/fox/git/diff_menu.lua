local M = {}
local ns = vim.api.nvim_create_namespace("fox_git_diff_menu")

function M.open(title, cards, confirm)
	local selected, regions = 1, {}
	local buf, win = require("fox.core.ui").float({ title = " " .. title .. " ", width = 1, height = 1 })
	vim.bo[buf].filetype = "fox_git_diff_menu"
	vim.wo[win].wrap = false
	local function draw()
		local width = math.max(1, math.min(150, vim.o.columns - 4))
		local wide = width >= 112 and #cards == 5
		local columns = wide and 4 or width >= 72 and 2 or 1
		local card_width = math.floor((width - columns + 1) / columns)
		local height = wide and 18 or 8
		local lines = { "Choose a card: 1-" .. #cards .. " / arrows / Tab. Enter confirms; Esc cancels.", "" }
		regions = {}
		for index, card in ipairs(cards) do
			local column = wide and math.min(index, 4) - 1 or (index - 1) % columns
			local row = wide and (index == 5 and 12 or 3) or 3 + math.floor((index - 1) / columns) * (height + 1)
			local size = wide and index >= 4 and 8 or height
			local content = { index .. ". " .. card.title, "", unpack(card.lines or {}) }
			local x = column * (card_width + 1)
			regions[index] = { row = row, x = x, height = size, width = card_width }
			for at = #lines + 1, row + size - 1 do
				lines[at] = ""
			end
			for offset = 0, size - 1 do
				local edge = offset == 0 or offset == size - 1
				local text = (content[offset] or ""):sub(1, math.max(0, card_width - 4))
				local cell = edge and ("+" .. string.rep("-", math.max(0, card_width - 2)) .. "+")
					or ("| " .. text .. string.rep(" ", math.max(0, card_width - 3 - #text)) .. "|")
				local at = row + offset
				lines[at] = (lines[at] or "") .. string.rep(" ", math.max(0, x - #(lines[at] or ""))) .. cell
			end
		end
		local view_height = math.max(1, math.min(#lines, vim.o.lines - 4))
		local row, col = require("fox.core.ui").center(width, view_height)
		vim.api.nvim_win_set_config(win, { relative = "editor", width = width, height = view_height, row = row, col = col })
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		local region = regions[selected]
		for at = region.row, region.row + region.height - 1 do
			vim.api.nvim_buf_set_extmark(buf, ns, at - 1, region.x, {
				end_col = region.x + region.width,
				hl_group = "Visual",
			})
		end
		vim.api.nvim_win_set_cursor(win, { region.row + 1, region.x })
	end
	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	local function map(key, callback)
		vim.keymap.set("n", key, callback, { buffer = buf, silent = true, nowait = true })
	end
	for index = 1, #cards do
		map(tostring(index), function()
			selected = index
			draw()
		end)
	end
	for key, delta in pairs({
		h = -1,
		k = -1,
		["<Left>"] = -1,
		["<Up>"] = -1,
		["<S-Tab>"] = -1,
		l = 1,
		j = 1,
		["<Right>"] = 1,
		["<Down>"] = 1,
		["<Tab>"] = 1,
	}) do
		map(key, function()
			selected = (selected - 1 + delta) % #cards + 1
			draw()
		end)
	end
	map("<CR>", function()
		close()
		confirm(selected)
	end)
	for _, key in ipairs({ "q", "<Esc>", "<C-c>" }) do
		map(key, close)
	end
	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("FoxGitDiffMenu" .. buf, { clear = true }),
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				draw()
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			vim.api.nvim_del_augroup_by_name("FoxGitDiffMenu" .. buf)
		end,
	})
	draw()
	return buf, win
end

return M
