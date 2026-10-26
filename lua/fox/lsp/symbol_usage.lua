-- Reference badges using document symbols and references from the attached LSP.
local M = {}
M.namespace = vim.api.nvim_create_namespace("fox_symbol_usage")
local buffers = {}
local options = { debounce = 300, kinds = { 5, 6, 11, 12, 23 } }
local function cancel(state)
	if state.timer then
		state.timer:stop()
		state.timer:close()
		state.timer = nil
	end
	for _, request in ipairs(state.requests or {}) do
		if request.client.cancel_request then
			pcall(request.client.cancel_request, request.client, request.id)
		end
	end
	state.requests = {}
end
local function invalidate(buf)
	local state = buffers[buf]
	if state then
		state.generation = state.generation + 1
		cancel(state)
	end
end
function M.clear(buf)
	invalidate(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
	end
end
local function state_for(buf)
	buffers[buf] = buffers[buf] or { generation = 0, requests = {} }
	return buffers[buf]
end
local function editing()
	local mode = vim.api.nvim_get_mode().mode
	return mode:match("^[iR]") ~= nil
end
function M.refresh(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= "" then
		return
	end
	local state = state_for(buf)
	invalidate(buf)
	-- Existing extmarks track edits. Incomplete syntax while typing must not
	-- replace the last complete snapshot or move the text below the cursor.
	if editing() then
		return
	end
	local generation, tick = state.generation, vim.api.nvim_buf_get_changedtick(buf)
	local client
	for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		if c:supports_method("textDocument/documentSymbol", buf) and c:supports_method("textDocument/references", buf) then
			client = c
			break
		end
	end
	if not client then
		M.clear(buf)
		return
	end
	local function valid()
		if
			not vim.api.nvim_buf_is_loaded(buf)
			or state.generation ~= generation
			or vim.api.nvim_buf_get_changedtick(buf) ~= tick
		then
			return false
		end
		for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
			if c.id == client.id then
				return true
			end
		end
		return false
	end
	local function request(method, params, callback)
		local ok, id = client:request(method, params, function(err, result)
			if valid() then
				callback(err, result)
			end
		end, buf)
		if ok and id then
			state.requests[#state.requests + 1] = { client = client, id = id }
		end
		return ok
	end
	local uri = vim.uri_from_bufnr(buf)
	request("textDocument/documentSymbol", { textDocument = { uri = uri } }, function(err, symbols)
		if err or type(symbols) ~= "table" then
			return
		end
		local entries, kinds = {}, {}
		for _, kind in ipairs(options.kinds) do
			kinds[kind] = true
		end
		local function visit(list)
			for _, symbol in ipairs(list) do
				local range = symbol.selectionRange or (symbol.location and symbol.location.range) or symbol.range
				if range and kinds[symbol.kind] and (not symbol.location or symbol.location.uri == uri) then
					entries[#entries + 1] = { position = range.start, row = (symbol.range or range).start.line }
				end
				if symbol.children then
					visit(symbol.children)
				end
			end
		end
		visit(symbols)
		local active, index = 0, 1
		local results, failed = {}, false
		local function render()
			vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
			for row, value in pairs(results) do
				if row < vim.api.nvim_buf_line_count(buf) then
					local chunks = options.text_format and options.text_format(value)
						or tostring(value.references) .. " references"
					if type(chunks) == "string" then
						chunks = { { chunks, "Comment" } }
					end
					vim.api.nvim_buf_set_extmark(buf, M.namespace, row, 0, { virt_lines = { chunks }, virt_lines_above = true })
				end
			end
		end
		if #entries == 0 then
			render()
			return
		end
		local pump
		pump = function()
			if not valid() then
				return
			end
			while active < 4 and index <= #entries do
				local entry = entries[index]
				index = index + 1
				active = active + 1
				local function done(error, refs)
					active = active - 1
					if not error and type(refs) == "table" then
						local value = results[entry.row] or { references = 0, stacked_count = -1 }
						-- Servers can duplicate locations, so count each URI/range once.
						local seen = {}
						for _, ref in ipairs(refs) do
							local key = vim.json.encode({ ref.uri, ref.range })
							if not seen[key] then
								value.references = value.references + 1
								seen[key] = true
							end
						end
						value.stacked_count = value.stacked_count + 1
						results[entry.row] = value
					else
						failed = true
					end
					-- Publish only a complete snapshot. Keep the old badges on
					-- transient server failures instead of flashing partial rows.
					if active == 0 and index > #entries then
						if not failed then
							render()
						end
					else
						pump()
					end
				end
				if
					not request(
						"textDocument/references",
						{ textDocument = { uri = uri }, position = entry.position, context = { includeDeclaration = false } },
						done
					)
				then
					done(true)
				end
			end
		end
		pump()
	end)
end
function M.schedule(buf)
	local state = state_for(buf)
	invalidate(buf)
	if editing() then
		return
	end
	local timer = (vim.uv or vim.loop).new_timer()
	state.timer = timer
	timer:start(
		options.debounce,
		0,
		vim.schedule_wrap(function()
			if state.timer ~= timer then
				return
			end
			if state.timer then
				state.timer:close()
				state.timer = nil
			end
			if vim.api.nvim_buf_is_loaded(buf) then
				M.refresh(buf)
			end
		end)
	)
end
function M.setup(opts)
	options = vim.tbl_extend("force", options, opts or {})
	local group = vim.api.nvim_create_augroup("fox_symbol_usage", { clear = true })
	vim.api.nvim_create_autocmd({ "LspAttach", "BufEnter", "TextChanged", "TextChangedI", "InsertLeave" }, {
		group = group,
		callback = function(ev)
			M.schedule(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd("InsertEnter", {
		group = group,
		callback = function(ev)
			invalidate(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(ev)
			M.clear(ev.buf)
			M.schedule(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(ev)
			M.clear(ev.buf)
			buffers[ev.buf] = nil
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			for buf in pairs(buffers) do
				M.clear(buf)
			end
		end,
	})
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if #vim.lsp.get_clients({ bufnr = buf }) > 0 then
			M.schedule(buf)
		end
	end
end
return M
