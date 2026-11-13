local t = require("fox.lib.foxnvim.test")
local m = require("fox.langs.php.laravel")
t.describe("FOX Laravel references", function()
	local root, buf, system, select
	local function write(name, lines)
		local file = root .. "/" .. name
		vim.fn.mkdir(vim.fs.dirname(file), "p")
		vim.fn.writefile(lines, file)
		return file
	end
	t.beforeEach(function()
		root = require("fox.core.path").normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
		system, select = vim.system, vim.ui.select
		vim.system = function()
			return { kill = function() end }
		end
		write("artisan", {})
		write("composer.json", { '{"autoload":{"psr-4":{"App\\\\":"app/","App\\\\Special\\\\":["special/","second/"]}}}' })
		write("resources/views/admin/home.blade.php", { "<p>Home</p>" })
		write("resources/views/components/alert.blade.php", { "<p>Alert</p>" })
		write("resources/views/livewire/counter.blade.php", { "<p>Counter</p>" })
		write("resources/views/vendor/mail/layout.blade.php", { "<p>Mail</p>" })
		write(
			"config/app.php",
			{ "<?php return [", "'name' => env('APP_NAME', 'Fox'),", "'nested' => ['enabled' => true],", "];" }
		)
		write(".env", { "APP_NAME=Fox" })
		write("lang/en/messages.php", { "<?php return ['welcome' => 'Welcome'];" })
		write("routes/web.php", { "<?php Route::get('/', fn () => view('admin.home'))->name('home');" })
		write("resources/js/Pages/Home.vue", { "<template />" })
		buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_name(buf, root .. "/test.php")
	end)
	t.afterEach(function()
		m.clear()
		vim.system, vim.ui.select = system, select
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		vim.fn.delete(root, "rf")
	end)
	t.it("indexes views, components, Livewire, routes, config/env, translations and Inertia by root", function()
		local index = m.index(root)
		for kind, key in pairs({
			view = "admin.home",
			component = "alert",
			livewire = "counter",
			route = "home",
			config = "app.nested.enabled",
			env = "APP_NAME",
			lang = "messages.welcome",
			inertia = "Home",
		}) do
			t.expect(index[kind][key] ~= nil).toBe(true)
		end
		t.expect(index.view["mail::layout"] ~= nil).toBe(true)
		t.expect(index.env.APP_NAME[1].value).toBe("Fox")
	end)
	t.it("parses nested PHP arrays, escapes and comments without evaluation", function()
		local keys =
			m.php_keys("<?php return [ 'outer' => [ 'inner' => 'a, b' ], /* 'fake' => [] */ 'end' => false ];", "app")
		t.expect(keys["app.outer.inner"].value).toBe("'a, b'")
		t.expect(keys["app.end"].value).toBe("false")
		t.expect(keys["app.fake"]).toBe(nil)
	end)
	t.it("selects the cursor's call and handles array arguments and Route::view", function()
		local line = "view('admin.home'); route('ho')"
		t.expect(m.context(line, #line - 2).kind).toBe("route")
		t.expect(m.context("<x-al", 5)).toEqual({ kind = "component", prefix = "al", start = 3 })
		local context = m.context("Route::view('/home', 'admin.h", 27)
		t.expect(context.kind).toBe("view")
		t.expect(m.context("@includeFirst(['admin.h", 22).kind).toBe("view")
	end)
	t.it("supports longest PSR-4 namespaces and array-valued paths", function()
		t.expect(m.class_paths(root, [[App\Special\Thing]]))
			.toEqual({ root .. "/special/Thing.php", root .. "/second/Thing.php" })
	end)
	t.it("cancels ambiguous navigation and isolates caches across roots", function()
		local other = vim.fn.tempname()
		vim.fn.mkdir(other .. "/resources/views", "p")
		vim.fn.writefile({ "Other" }, other .. "/resources/views/other.blade.php")
		t.expect(m.index(other).view["admin.home"]).toBe(nil)
		t.expect(m.index(root).view["other"]).toBe(nil)
		vim.fn.delete(other, "rf")
		write("app/View/Components/Alert.php", { "<?php class Alert {}" })
		m.clear()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<x-alert />" })
		vim.api.nvim_win_set_cursor(0, { 1, 5 })
		vim.ui.select = function(_, _, cb)
			cb(nil)
		end
		m.goto_file()
		t.expect(vim.api.nvim_get_current_buf()).toBe(buf)
	end)
	t.it("completes only the reference range with closers and invokes callback once", function()
		local source = require("fox.langs.php.blink").new()
		local result, count = nil, 0
		local line = "<x-al"
		source:get_completions({ bufnr = buf, line = line, cursor = { 1, #line } }, function(value)
			result = value
			count = count + 1
		end)
		vim.wait(1000, function()
			return result ~= nil
		end)
		t.expect(count).toBe(1)
		t.expect(result.items[1].textEdit.newText).toBe("alert />")
		t.expect(result.items[1].textEdit.range.start.character).toBe(3)
		result = nil
		local cancel = source:get_completions({ bufnr = buf, line = "view('admin.h", cursor = { 1, 13 } }, function()
			count = count + 1
		end)
		cancel()
		vim.wait(20, function()
			return false
		end)
		t.expect(count).toBe(1)
	end)
	t.it("installs the helper exclusively and preserves an existing divergent file", function()
		m.install_helper()
		local file = root .. "/app/Console/Commands/BladeNav.php"
		t.expect(vim.fn.filereadable(file)).toBe(1)
		vim.fn.writefile({ "user helper" }, file)
		m.install_helper()
		t.expect(vim.fn.readfile(file)).toEqual({ "user helper" })
	end)
	t.it("resolves runtime routes to controller methods with async process output", function()
		write("app/Http/Controllers/Home.php", { "<?php", "class Home {", " public function show() {}", "}" })
		local callback
		local executable = vim.fn.executable
		vim.fn.executable = function()
			return 1
		end
		vim.system = function(_, _, cb)
			callback = cb
			return { kill = function() end }
		end
		local index = m.index(root)
		callback({ code = 0, stdout = '[{"name":"runtime","action":"App\\\\Http\\\\Controllers\\\\Home@show"}]' })
		vim.wait(50, function()
			return index.route.runtime ~= nil
		end)
		vim.fn.executable = executable
		t.expect(index.route.runtime[1].row).toBe(3)
	end)
	t.it("rejects stale Artisan responses after clearing the index", function()
		local callback
		local executable = vim.fn.executable
		vim.fn.executable = function()
			return 1
		end
		vim.system = function(_, _, cb)
			callback = cb
			return { kill = function() end }
		end
		local index = m.index(root)
		m.clear()
		callback({ code = 0, stdout = '[{"name":"late","action":"App\\\\Http\\\\Controllers\\\\Gone"}]' })
		vim.wait(20, function()
			return false
		end)
		vim.fn.executable = executable
		t.expect(index.route.late).toBe(nil)
	end)
end)
