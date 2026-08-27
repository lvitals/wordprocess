--!nonstrict

-- Frontend smoke test: spawns the real `wp` binary in a pseudo-terminal
-- (via the ptysmoke helper next to this file) and checks a handful of
-- properties that live entirely below the Lua/wg boundary the rest of
-- tests/ mocks out with wg.getscreensize() + RedrawScreen(). That mock
-- catches viewport/wrap/layout bugs (see wrapped-paragraph-scroll-up.lua)
-- but cannot see a bug in the *translation* from a logical cell to actual
-- terminal bytes -- which is exactly where recent regressions lived (a
-- hardcoded pixel height in the GLFW frontend, a stale window-size offset).
-- This is deliberately not a VT100 emulator or a byte-for-byte screen
-- comparison -- too fragile to maintain -- just a few specific properties:
--
--   - the process survives startup, several resizes, and normal
--     navigation, and exits cleanly on request;
--   - after a resize, any cursor-positioning escape sequences emitted
--     address a row/column that exists in the *new* size, not a stale one
--     left over from before the resize;
--   - with TERM=linux (the one terminal type this app explicitly detects
--     and downgrades for -- see enable_unicode in src/c/main.c), the
--     output never contains a raw byte the console couldn't render.

local wp_binary, ptysmoke_binary = ...
if not wp_binary or not ptysmoke_binary then
	error("usage: wp --lua tests/frontend/wp-pty-smoke.lua <wp-binary> <ptysmoke-binary>")
end

loadfile("tests/testsuite.lua")()

local function hex_encode(s)
	return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function hex_decode(s)
	return (s:gsub("%x%x", function(cc) return string.char(tonumber(cc, 16)) end))
end

-- Runs one ptysmoke command script (see ptysmoke.c) and returns its result
-- lines, one per command, in the order the commands were given.
local function run_ptysmoke(commands)
	local scratch = wg.mkdtemp()
	local scriptfile = scratch .. "/commands.txt"
	local _, err = wg.writefile(scriptfile, table.concat(commands, "\n") .. "\n")
	if err then
		error("failed to write ptysmoke command script: " .. tostring(err))
	end

	local f = io.popen(string.format("'%s' < '%s'", ptysmoke_binary, scriptfile), "r")
	if not f then
		error("failed to launch ptysmoke")
	end

	local lines = {}
	for line in f:lines() do
		lines[#lines + 1] = line
	end
	f:close()
	return lines
end

local function step_spawn(binary, home, rows, cols, term)
	return {
		cmd = string.format("SPAWN %s %s %d %d %s", binary, home, rows, cols, term),
		check = function(line)
			if line ~= "SPAWN 1" then
				error("failed to spawn " .. binary .. ": " .. tostring(line))
			end
		end,
	}
end

local function step_send(bytes)
	return {
		cmd = "SEND_HEX " .. hex_encode(bytes),
		check = function(line)
			if line ~= "SEND_HEX 1" then
				error("SEND_HEX failed: " .. tostring(line))
			end
		end,
	}
end

local function step_resize(rows, cols)
	return {
		cmd = string.format("RESIZE %d %d", rows, cols),
		check = function(line)
			if line ~= "RESIZE 1" then
				error("RESIZE failed: " .. tostring(line))
			end
		end,
	}
end

local function step_alive(label)
	return {
		cmd = "ALIVE",
		check = function(line)
			if line ~= "ALIVE 1" then
				error(label .. ": process is no longer running")
			end
		end,
	}
end

local function step_wait_exit(ms)
	return {
		cmd = "WAIT_EXIT " .. ms,
		check = function(line)
			if line ~= "WAIT_EXIT 1" then
				error("process did not exit within the timeout after being asked to quit")
			end
		end,
	}
end

-- Every cursor-positioning sequence this app's ncurses backend can emit
-- (see dpy_setcursor -> curses move() -> the cursor_address/row_address/
-- column_address terminfo capabilities): CUP "row;colH", VPA "rowd", CHA
-- "colG". A stale reference to a size from *before* the last resize is
-- exactly the class of bug a wg.getscreensize() mock cannot catch, because
-- it never has real terminal coordinates to get wrong.
local function check_cursor_in_bounds(rows, cols)
	return function(data)
		for rowstr, colstr in data:gmatch("\27%[(%d+);(%d+)H") do
			local row, col = tonumber(rowstr), tonumber(colstr)
			if row < 1 or row > rows or col < 1 or col > cols then
				error(string.format(
					"cursor move to row %d, col %d is out of bounds for a %dx%d terminal",
					row, col, cols, rows))
			end
		end
		for rowstr in data:gmatch("\27%[(%d+)d") do
			local row = tonumber(rowstr)
			if row < 1 or row > rows then
				error(string.format(
					"cursor move to row %d is out of bounds for a %dx%d terminal", row, cols, rows))
			end
		end
		for colstr in data:gmatch("\27%[(%d+)G") do
			local col = tonumber(colstr)
			if col < 1 or col > cols then
				error(string.format(
					"cursor move to col %d is out of bounds for a %dx%d terminal", col, cols, rows))
			end
		end
	end
end

local function step_drain(ms, checkdata)
	return {
		cmd = "DRAIN " .. ms,
		check = function(line)
			local hex = line:match("^DATA (%x*)$")
			if not hex then
				error("expected a DATA result line, got: " .. tostring(line))
			end
			local data = hex_decode(hex)
			if data:find("Lua error", 1, true) or data:find("stack traceback", 1, true) then
				error("output contains a Lua error:\n" .. data)
			end
			if checkdata then
				checkdata(data)
			end
		end,
	}
end

local function run_session(steps)
	local commands = {}
	for i, step in ipairs(steps) do
		commands[i] = step.cmd
	end

	local lines = run_ptysmoke(commands)
	if #lines < #commands then
		error(string.format(
			"ptysmoke produced %d result line(s) for %d command(s) -- " ..
			"it may have crashed; last line: %s",
			#lines, #commands, lines[#lines] or "(none)"))
	end

	for i, step in ipairs(steps) do
		step.check(lines[i])
	end
end

-- Spawn, resize through several sizes, navigate, and exit cleanly: no
-- hang, no crash, no leftover process, and no stale cursor coordinates
-- surviving a resize.
local function test_core_smoke()
	local home = wg.mkdtemp()
	local steps = {
		step_spawn(wp_binary, home, 24, 80, "xterm-256color"),
		step_drain(3000), -- let startup settle
		step_alive("after startup"),

		step_send("\27OB"), -- Down
		step_drain(500),
		step_alive("after Down"),

		step_send("\27OA"), -- Up
		step_drain(500),
		step_alive("after Up"),
	}

	for _, size in ipairs({{40, 120}, {15, 40}, {60, 200}, {24, 80}}) do
		local rows, cols = size[1], size[2]
		steps[#steps + 1] = step_resize(rows, cols)
		steps[#steps + 1] = step_drain(500, check_cursor_in_bounds(rows, cols))
		steps[#steps + 1] = step_alive(string.format("after resize to %dx%d", cols, rows))
	end

	steps[#steps + 1] = step_send("\17") -- Ctrl+Q, the "Exit" accelerator
	steps[#steps + 1] = step_wait_exit(10000)

	run_session(steps)
end

-- With TERM=linux, this app explicitly downgrades to ASCII-only rendering
-- (see enable_unicode in src/c/main.c) because the Linux console's default
-- font lacks the box-drawing/block glyphs used elsewhere. The very first
-- screen (which includes the terminator ruler, on by default) must honour
-- that -- not just pick prettier fallback glyphs, but never emit a raw
-- byte >= 0x80 at all.
local function test_restricted_term_ascii_only()
	local home = wg.mkdtemp()
	local steps = {
		step_spawn(wp_binary, home, 24, 80, "linux"),
		step_drain(3000, function(data)
			for i = 1, #data do
				if data:byte(i) >= 0x80 then
					error(string.format(
						"TERM=linux startup emitted a byte >= 0x80 at offset %d " ..
						"of %d -- that console cannot render it", i, #data))
				end
			end
		end),
		step_alive("restricted-terminal startup"),
		step_send("\17"),
		step_wait_exit(10000),
	}
	run_session(steps)
end

test_core_smoke()
test_restricted_term_ascii_only()
