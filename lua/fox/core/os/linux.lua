-- Kernel keyboard LED state works on local X11, Wayland and console sessions.
-- No compositor commands, shell processes, privileges or writable device access.
local M = { led_root = "/sys/class/leds" }

function M.is_caps_lock_on()
	local scan = (vim.uv or vim.loop).fs_scandir(M.led_root)
	if not scan then
		return false
	end
	while true do
		local name = (vim.uv or vim.loop).fs_scandir_next(scan)
		if not name then
			break
		end
		if name:match(":capslock$") then
			local file = io.open(M.led_root .. "/" .. name .. "/brightness", "r")
			if file then
				local value = tonumber(file:read("*l"))
				file:close()
				if value and value > 0 then
					return true
				end
			end
		end
	end
	return false
end

return M
