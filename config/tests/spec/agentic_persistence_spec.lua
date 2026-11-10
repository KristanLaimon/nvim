local t = require("fox.lib.foxnvim.test")

t.describe("Codex launcher persistence", function()
	if vim.fn.executable("codex") ~= 1 then
		return
	end
	t.it("makes a blank session readable and resumable by independent clients without a model turn", function()
		local provider = require("fox.agentic.providers.codex")
		local root = vim.fn.tempname() .. "-codex-persistence"
		vim.fn.mkdir(root, "p")
		local connections = {}
		local function connect(ready, status)
			local original = vim.env.CODEX_HOME
			vim.env.CODEX_HOME = root
			local connection = provider.connect(ready, function() end, status)
			vim.env.CODEX_HOME = original
			connections[#connections + 1] = connection
			return connection
		end
		local ok, err = pcall(function()
			local done, failure, session = false, nil, nil
			local creator = connect(function(connection)
				provider.create_session(connection, root, function(result, create_error)
					session, failure, done = result, create_error, true
				end)
			end, function(status)
				failure = status
				done = true
			end)
			assert(
				vim.wait(15000, function()
					return done
				end, 10),
				"Codex creation timed out"
			)
			assert(session and not failure, failure)
			creator.detach(true)
			done = false
			connect(function(connection)
				connection.request("thread/read", { threadId = session.id, includeTurns = false }, function(result, read_error)
					if read_error then
						failure = read_error
						done = true
						return
					end
					assert(result.thread.id == session.id)
					connection.request(
						"thread/resume",
						{ threadId = session.id, excludeTurns = true },
						function(resumed, resume_error)
							failure = resume_error or (not resumed and "Empty resume response")
							if resumed then
								assert(resumed.thread.id == session.id and #resumed.thread.turns == 0)
							end
							done = true
						end
					)
				end)
			end, function(status)
				failure = status
				done = true
			end)
			assert(
				vim.wait(15000, function()
					return done
				end, 10),
				"Independent Codex client timed out"
			)
			assert(not failure, failure)
		end)
		for _, connection in ipairs(connections) do
			connection.detach(true)
		end
		vim.fn.delete(root, "rf")
		assert(ok, err)
	end)
end)
