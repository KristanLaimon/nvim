local M = {}

-- Local reference for Laravel Blade and the Livewire directives supported by FoxVim.
local directives = {
	["if"] = { "if($condition)", "Renders the block when the condition is true. Close it with `@endif`." },
	["elseif"] = { "elseif($condition)", "Tests another condition when the earlier branches did not match." },
	["else"] = { "else", "Renders the fallback branch of the enclosing conditional." },
	endif = { "endif", "Closes an `@if`, `@hasSection`, `@sectionMissing`, or `@hasstack` block." },
	unless = { "unless($condition)", "Renders the block when the condition is false. Close it with `@endunless`." },
	endunless = { "endunless", "Closes an `@unless` block." },
	isset = { "isset($value)", "Renders the block when the value is defined and non-null." },
	endisset = { "endisset", "Closes an `@isset` block." },
	empty = { "empty($value)", "Tests whether a value is empty, or starts the fallback branch inside `@forelse`." },
	endempty = { "endempty", "Closes an `@empty($value)` conditional." },
	["switch"] = { "switch($value)", "Starts a switch with `@case` branches and an optional `@default`." },
	case = { "case($value)", "Starts a matching branch of a switch." },
	default = { "default", "Starts the fallback branch of a switch." },
	endswitch = { "endswitch", "Closes an `@switch` block." },
	["for"] = { "for($i = 0; $i < $count; $i++)", "Starts a counted loop. Close it with `@endfor`." },
	endfor = { "endfor", "Closes a `@for` loop." },
	foreach = { "foreach($items as $item)", "Iterates over a collection. Use `$loop` for loop metadata." },
	endforeach = { "endforeach", "Closes a `@foreach` loop." },
	forelse = { "forelse($items as $item)", "Iterates over a collection with an `@empty` branch for an empty iterable." },
	endforelse = { "endforelse", "Closes a `@forelse` loop." },
	["while"] = { "while($condition)", "Repeats the block while the condition is true." },
	endwhile = { "endwhile", "Closes a `@while` loop." },
	["break"] = { "break($condition)", "Exits the current loop or switch. Omit the condition to always exit." },
	continue = { "continue($condition)", "Skips to the next iteration. Omit the condition to always skip." },
	auth = { "auth($guard)", "Renders for an authenticated user, optionally using the given guard." },
	elseauth = { "elseauth($guard)", "Checks another guard in an authentication conditional." },
	endauth = { "endauth", "Closes an `@auth` block." },
	guest = { "guest($guard)", "Renders for a guest, optionally using the given guard." },
	elseguest = { "elseguest($guard)", "Checks another guard in a guest conditional." },
	endguest = { "endguest", "Closes a `@guest` block." },
	can = { "can($ability, $model)", "Renders if the current user is authorized for this ability." },
	elsecan = { "elsecan($ability, $model)", "Tests another ability in an authorization conditional." },
	endcan = { "endcan", "Closes a `@can` block." },
	cannot = { "cannot($ability, $model)", "Renders if the current user lacks this ability." },
	elsecannot = { "elsecannot($ability, $model)", "Tests for the absence of another ability." },
	endcannot = { "endcannot", "Closes a `@cannot` block." },
	canany = { "canany($abilities, $model)", "Renders if the current user has at least one of the listed abilities." },
	elsecanany = { "elsecanany($abilities, $model)", "Tests a second list of abilities." },
	endcanany = { "endcanany", "Closes a `@canany` block." },
	extends = { "extends('layouts.app')", "Uses a parent Blade view as the layout for this template." },
	section = {
		"section('content')",
		"Defines a named layout section. An optional second argument supplies inline content.",
	},
	endsection = { "endsection", "Finishes defining a layout section." },
	show = { "show", "Finishes defining the current section and renders it at this location." },
	stop = { "stop", "Finishes defining the current layout section." },
	append = { "append", "Appends the current block to an existing section." },
	overwrite = { "overwrite", "Replaces any existing content of the current section." },
	parent = { "parent", "Inserts the inherited section content into an overriding section." },
	yield = { "yield('content', $default)", "Renders a named layout section with an optional fallback value." },
	hasSection = { "hasSection('content')", "Renders the block if the named section contains content." },
	sectionMissing = { "sectionMissing('content')", "Renders the block if the named section is missing or empty." },
	include = { "include('partials.form', $data)", "Renders another Blade view with access to the current view data." },
	includeIf = { "includeIf('partials.form', $data)", "Includes a view if it exists." },
	includeWhen = { "includeWhen($condition, 'partials.form', $data)", "Includes a view when the condition is true." },
	includeUnless = {
		"includeUnless($condition, 'partials.form', $data)",
		"Includes a view when the condition is false.",
	},
	includeFirst = { "includeFirst($views, $data)", "Includes the first existing view from the list." },
	each = {
		"each('partials.item', $items, 'item', 'partials.empty')",
		"Renders a view per item, with an optional empty view.",
	},
	component = { "component('components.card', $data)", "Renders a component with block content and optional data." },
	endcomponent = { "endcomponent", "Closes a `@component` block." },
	slot = { "slot('header')", "Supplies content for a named component slot." },
	endslot = { "endslot", "Closes a `@slot` block." },
	props = { "props(['type' => 'info'])", "Declares props and default values for an anonymous component." },
	aware = { "aware(['color' => 'gray'])", "Reads explicit attributes from a parent Blade component." },
	stack = { "stack('scripts')", "Renders the contents collected for a named stack." },
	hasstack = { "hasstack('scripts')", "Renders the block when the named stack contains content." },
	push = { "push('scripts')", "Adds content to the end of a named stack." },
	endpush = { "endpush", "Closes a `@push` block." },
	pushIf = { "pushIf($condition, 'scripts')", "Adds content to the stack when the condition is true." },
	endPushIf = { "endPushIf", "Closes a `@pushIf` block." },
	prepend = { "prepend('styles')", "Adds content to the beginning of a named stack." },
	endprepend = { "endprepend", "Closes a `@prepend` block." },
	pushOnce = {
		"pushOnce('scripts', $id)",
		"Pushes content once per render cycle. The optional ID deduplicates separate blocks.",
	},
	endPushOnce = { "endPushOnce", "Closes a `@pushOnce` block." },
	prependOnce = {
		"prependOnce('styles', $id)",
		"Prepends content once per render cycle using an optional deduplication ID.",
	},
	endPrependOnce = { "endPrependOnce", "Closes a `@prependOnce` block." },
	once = { "once", "Evaluates this block once per rendering cycle." },
	endonce = { "endonce", "Closes an `@once` block." },
	csrf = { "csrf", "Renders the hidden CSRF token field for an HTML form." },
	method = { "method('PUT')", "Renders the hidden field used to override an HTML form's HTTP method." },
	error = { "error('email', $bag)", "Renders a validation error block and exposes its text as `$message`." },
	enderror = { "enderror", "Closes an `@error` block." },
	["class"] = { "class($classes)", "Builds a class attribute from unconditional and conditionally enabled classes." },
	style = { "style($styles)", "Builds an inline style attribute from conditional declarations." },
	checked = { "checked($condition)", "Emits the HTML checked attribute when the condition is true." },
	selected = { "selected($condition)", "Emits the HTML selected attribute when the condition is true." },
	disabled = { "disabled($condition)", "Emits the HTML disabled attribute when the condition is true." },
	readonly = { "readonly($condition)", "Emits the HTML readonly attribute when the condition is true." },
	required = { "required($condition)", "Emits the HTML required attribute when the condition is true." },
	inject = { "inject('service', Service::class)", "Resolves a service from Laravel's container into a view variable." },
	use = { "use('App\\Models\\User')", "Imports a PHP class into the template, optionally with an alias." },
	php = { "php", "Starts a plain PHP block. Close it with `@endphp`." },
	endphp = { "endphp", "Closes a plain PHP block." },
	verbatim = { "verbatim", "Keeps Blade from compiling template syntax inside this block." },
	endverbatim = { "endverbatim", "Closes a verbatim block." },
	env = { "env('staging')", "Renders the block for the specified environment or list of environments." },
	endenv = { "endenv", "Closes an `@env` block." },
	production = { "production", "Renders the block in the production environment." },
	endproduction = { "endproduction", "Closes a `@production` block." },
	session = { "session('status')", "Renders when the session key exists and exposes the entry as `$value`." },
	endsession = { "endsession", "Closes a `@session` block." },
	fragment = { "fragment('content')", "Marks a view fragment that can be rendered separately in an HTTP response." },
	endfragment = { "endfragment", "Closes a `@fragment` block." },
	json = { "json($value)", "Encodes a value as JSON." },
	js = { "js($value)", "Produces a JavaScript expression for the given PHP value." },
	vite = { "vite('resources/js/app.js')", "Adds the tags for the selected Vite entry points." },
	livewire = { "livewire('counter')", "Renders a Livewire component by name." },
	script = { "script", "Runs the enclosed JavaScript when this Livewire component initializes." },
	endscript = { "endscript", "Closes a Livewire `@script` block." },
	assets = { "assets", "Loads the enclosed scripts and styles once per page for the Livewire component." },
	endassets = { "endassets", "Closes a Livewire `@assets` block." },
}

local function is_directive_start(line, start)
	local before = line:sub(1, start - 1)
	if before:match("[%w_@%.+-]$") then
		return false
	end
	local comment_start = before:match(".*(){{%-%-")
	local comment_end = before:match(".*()%-%-}}")
	return not comment_start or (comment_end and comment_end > comment_start)
end

local function documentation(entry)
	return { ("`@%s`"):format(entry[1]), "", entry[2] }
end

function M.under_cursor(line, col)
	for start, name, after in line:gmatch("()@([%a_][%w_]*)()") do
		local entry = directives[name]
		if col >= start - 1 and col < after - 1 and entry and is_directive_start(line, start) then
			return documentation(entry)
		end
	end
end

function M.complete(line, row, col)
	local start, prefix = line:sub(1, col):match("()@([%w_]*)$")
	if not start or not is_directive_start(line, start) then
		return nil
	end

	local suffix = line:sub(col + 1):match("^[%w_]*")
	local items = {}
	for name, entry in pairs(directives) do
		if vim.startswith(name, prefix) then
			items[#items + 1] = {
				label = "@" .. name,
				filterText = name,
				kind = vim.lsp.protocol.CompletionItemKind.Keyword,
				detail = "Blade directive",
				documentation = { kind = "markdown", value = table.concat(documentation(entry), "\n") },
				textEdit = {
					range = {
						start = { line = row, character = start - 1 },
						["end"] = { line = row, character = col + #suffix },
					},
					newText = "@" .. name,
				},
			}
		end
	end
	return items
end

return M
