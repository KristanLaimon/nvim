-- Retain :Telescope notify for users of the former plugin's history picker.
return require("telescope").register_extension({
	exports = {
		notify = function(opts)
			opts = opts or {}
			local notify = require("fox.core.notify")
			local records = notify.history()
			for i = 1, math.floor(#records / 2) do
				records[i], records[#records - i + 1] = records[#records - i + 1], records[i]
			end
			local actions = require("telescope.actions")
			require("telescope.pickers")
				.new(opts, {
					prompt_title = "Notifications",
					finder = require("telescope.finders").new_table({
						results = records,
						entry_maker = function(record)
							local text = table.concat(record.title, " ") .. " " .. table.concat(record.message, " ")
							return { value = record, display = record.level .. " " .. text, ordinal = text }
						end,
					}),
					sorter = require("telescope.config").values.generic_sorter(opts),
					attach_mappings = function(prompt)
						actions.select_default:replace(function()
							local entry = require("telescope.actions.state").get_selected_entry()
							actions.close(prompt)
							if entry then
								vim.api.nvim_set_current_buf(notify.open(entry.value).buffer)
							end
						end)
						return true
					end,
				})
				:find()
		end,
	},
})
