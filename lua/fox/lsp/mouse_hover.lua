-- Hover documentation at the pointer without moving the editing cursor.
local M = {}
local generation = 0
local hover_win
local last_position

function M.close()
	generation = generation + 1
	last_position = nil
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		vim.api.nvim_win_close(hover_win, true)
	end
	hover_win = nil
end

function M.move()
	local mouse = vim.fn.getmousepos()
	if mouse.winid == hover_win then
		return
	end
	local position = table.concat({ mouse.winid, mouse.line, mouse.column, mouse.screenrow, mouse.screencol }, ":")
	if position == last_position then
		return
	end
	M.close()
	last_position = position
	local win = mouse.winid
	if win == 0 or not vim.api.nvim_win_is_valid(win) or mouse.line < 1 or mouse.column < 1 then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.bo[buf].buftype ~= "" or vim.api.nvim_win_get_config(win).relative ~= "" then
		return
	end
	if vim.fn.screenpos(win, mouse.line, mouse.column).row ~= mouse.screenrow then
		return
	end
	local line = vim.api.nvim_buf_get_lines(buf, mouse.line - 1, mouse.line, false)[1] or ""
	if mouse.column > #line or line:sub(mouse.column, mouse.column):match("%s") then
		return
	end
	local version = generation
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	vim.defer_fn(function()
		if version ~= generation or not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/hover" })) do
			local params = {
				textDocument = { uri = vim.uri_from_bufnr(buf) },
				position = {
					line = mouse.line - 1,
					character = vim.str_utfindex(line, client.offset_encoding, mouse.column - 1, false),
				},
			}
			client:request("textDocument/hover", params, function(err, result)
				if err or not result or not result.contents or version ~= generation or hover_win then
					return
				end
				if
					not vim.api.nvim_buf_is_valid(buf)
					or vim.api.nvim_buf_get_changedtick(buf) ~= tick
					or not vim.api.nvim_win_is_valid(win)
					or vim.api.nvim_win_get_buf(win) ~= buf
				then
					return
				end
				local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
				if vim.tbl_isempty(lines) then
					return
				end
				local _, float = vim.lsp.util.open_floating_preview(lines, "markdown", {
					relative = "mouse",
					border = "rounded",
					focus = false,
					focusable = false,
					max_width = 80,
					max_height = 20,
					close_events = { "BufLeave", "InsertCharPre", "CursorMoved", "CursorMovedI" },
				})
				hover_win = float
			end, buf)
		end
	end, 400)
end

return M
