-- OmniSharp's extended protocol resolves decompiled and generated C# sources.
-- Requests remain asynchronous; returned sources live in readonly scratch buffers.
local M = {}
local generations = {}
local methods = {
	definition = "o#/v2/gotodefinition",
	type_definition = "o#/gototypedefinition",
	references = "o#/findusages",
	implementation = "o#/findimplementations",
}
local function warn(err)
	vim.notify("OmniSharp: " .. tostring(type(err) == "table" and err.message or err), vim.log.levels.WARN)
end
local function present(value)
	return value ~= nil and value ~= vim.NIL
end
function M.source_buffer(client, response)
	if type(response) ~= "table" or type(response.Source) ~= "string" or type(response.SourceName) ~= "string" then
		return
	end
	local uri = "omnisharp://" .. client.id .. "/" .. vim.uri_encode(response.SourceName, "rfc3986")
	local buf = vim.uri_to_bufnr(uri)
	vim.fn.bufload(buf)
	-- Never replace user changes, even if a caller has manually unlocked the buffer.
	if
		vim.bo[buf].modified
		or (vim.b[buf].fox_omnisharp_tick and vim.b[buf].fox_omnisharp_tick ~= vim.api.nvim_buf_get_changedtick(buf))
	then
		return
	end
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	vim.bo[buf].readonly = false
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response.Source:gsub("\r\n", "\n"), "\n", { plain = true }))
	vim.bo[buf].filetype = "cs"
	vim.bo[buf].modified = false
	vim.bo[buf].readonly = true
	vim.bo[buf].modifiable = false
	vim.b[buf].fox_omnisharp_filename = response.SourceName
	vim.b[buf].fox_omnisharp_tick = vim.api.nvim_buf_get_changedtick(buf)
	if vim.lsp.get_client_by_id(client.id) then
		vim.lsp.buf_attach_client(buf, client.id)
	end
	return vim.uri_from_bufnr(buf)
end
function M.resolve(client, result, callback, valid)
	valid = valid or function()
		return true
	end
	if type(result) ~= "table" then
		callback({})
		return
	end
	local entries = result.Definitions or result.QuickFixes or {}
	if entries == vim.NIL then
		entries = {}
	end
	local locations, remaining = {}, #entries
	if remaining == 0 then
		callback({})
		return
	end
	local function done(index, entry, uri)
		if not valid() then
			return
		end
		if uri then
			local loc = entry.Location or entry
			local r = loc.Range
			local start = r and r.Start or { Line = loc.Line, Column = loc.Column }
			local finish = r and r.End or { Line = loc.EndLine or loc.Line, Column = loc.EndColumn or loc.Column }
			if start and finish and type(start.Line) == "number" and type(start.Column) == "number" then
				locations[index] = {
					uri = uri,
					range = {
						start = { line = start.Line, character = start.Column },
						["end"] = {
							line = finish.Line,
							character = finish.Column,
						},
					},
				}
			end
		end
		remaining = remaining - 1
		if remaining == 0 then
			local ordered = {}
			for i = 1, #entries do
				if locations[i] then
					ordered[#ordered + 1] = locations[i]
				end
			end
			callback(ordered)
		end
	end
	for i, entry in ipairs(entries) do
		local loc = entry.Location or entry
		local metadata = present(entry.MetadataSource) and entry.MetadataSource
		local generated = present(entry.SourceGeneratedFileInfo) and entry.SourceGeneratedFileInfo
			or (present(entry.GeneratedFileInfo) and entry.GeneratedFileInfo)
		if metadata or generated then
			local params = vim.deepcopy(generated or metadata)
			params.timeout = 5000
			local accepted = client:request(
				generated and "o#/sourcegeneratedfile" or "o#/metadata",
				params,
				function(err, response)
					if not valid() then
						return
					end
					if err then
						warn(err)
					end
					done(i, entry, not err and M.source_buffer(client, response) or nil)
				end
			)
			if not accepted then
				done(i, entry, nil)
			end
		else
			done(i, entry, type(loc.FileName) == "string" and vim.uri_from_fname(loc.FileName) or nil)
		end
	end
end
function M.show(locations, client, opts)
	opts = opts or {}
	if #locations == 0 then
		vim.notify("No locations found", vim.log.levels.INFO)
		return
	end
	if #locations == 1 and opts.jump_type ~= "never" then
		if opts.jump_type == "tab" then
			vim.cmd.tabnew()
		elseif opts.jump_type == "split" then
			vim.cmd.split()
		elseif opts.jump_type == "vsplit" then
			vim.cmd.vsplit()
		end
		vim.lsp.util.show_document(
			locations[1],
			client.offset_encoding or "utf-16",
			{ focus = true, reuse_win = opts.reuse_win ~= false }
		)
		return
	end
	local items = vim.lsp.util.locations_to_items(locations, client.offset_encoding or "utf-16")
	if opts.telescope and pcall(require, "telescope.pickers") then
		local conf = require("telescope.config").values
		require("telescope.pickers")
			.new(opts, {
				prompt_title = "C# locations",
				finder = require("telescope.finders").new_table({
					results = items,
					entry_maker = require("telescope.make_entry").gen_from_quickfix(opts),
				}),
				previewer = conf.qflist_previewer(opts),
				sorter = conf.generic_sorter(opts),
			})
			:find()
	else
		vim.fn.setqflist({}, " ", { title = "C# locations", items = items })
		vim.cmd.copen()
	end
end
function M.request(kind, opts, context)
	local buf = context and context.bufnr or vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end
	local client = context and vim.lsp.get_client_by_id(context.client_id)
	if not client then
		for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
			if c.name == "omnisharp" or c.name == "omnisharp_mono" then
				client = c
				break
			end
		end
	end
	if not client then
		return
	end
	local cursor = vim.api.nvim_win_get_cursor(win)
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local generation = (generations[buf] or 0) + 1
	generations[buf] = generation
	local function valid()
		return generations[buf] == generation
			and vim.api.nvim_buf_is_valid(buf)
			and vim.api.nvim_win_is_valid(win)
			and vim.api.nvim_get_current_win() == win
			and vim.api.nvim_win_get_buf(win) == buf
			and vim.api.nvim_buf_get_changedtick(buf) == tick
			and vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
			and vim.lsp.get_client_by_id(client.id) ~= nil
	end
	local position = context and context.params and context.params.position
		or vim.lsp.util.make_position_params(win, client.offset_encoding or "utf-16").position
	local params = {
		fileName = vim.b[buf].fox_omnisharp_filename or vim.api.nvim_buf_get_name(buf),
		line = position.line,
		column = position.character,
		excludeDefinition = opts and opts.excludeDefinition or false,
		WantMetadata = true,
	}
	client:request(assert(methods[kind]), params, function(err, result)
		if not valid() then
			return
		end
		if err then
			warn(err)
			return
		end
		M.resolve(client, result, function(locations)
			if valid() then
				M.show(locations, client, opts)
			end
		end, valid)
	end, buf)
end
local function handler(kind, err, result, ctx)
	if err then
		warn(err)
		return
	end
	if not result or result == vim.NIL then
		return
	end
	local locations = vim.islist(result) and result or { result }
	local extended = false
	for _, location in ipairs(locations) do
		local uri = location.uri or location.targetUri
		if
			uri
			and (
				uri:find("%$metadata%$")
				or uri:match("^omnisharp:")
				or (uri:match("^file:") and not (vim.uv or vim.loop).fs_stat(vim.uri_to_fname(uri)))
			)
		then
			extended = true
			break
		end
	end
	if extended or (vim.api.nvim_buf_is_valid(ctx.bufnr or 0) and vim.b[ctx.bufnr or 0].fox_omnisharp_filename) then
		return M.request(kind, nil, ctx)
	end
	local client = vim.lsp.get_client_by_id(ctx.client_id)
	if client then
		M.show(locations, client)
	end
end
for kind in pairs(methods) do
	M[kind .. "_handler"] = function(err, result, ctx)
		return handler(kind, err, result, ctx)
	end
	M["lsp_" .. kind] = function(opts)
		return M.request(kind, opts)
	end
	M["telescope_lsp_" .. kind] = function(opts)
		return M.request(kind, vim.tbl_extend("force", opts or {}, { telescope = true }))
	end
end
M.handler = M.definition_handler
M.lsp_definitions = M.lsp_definition
M.telescope_lsp_definitions = M.telescope_lsp_definition
return M
