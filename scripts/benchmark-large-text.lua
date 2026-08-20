-- Benchmarks the native mapped piece-table backend without modifying the
-- source. Usage: wp --lua scripts/benchmark-large-text.lua FILE

local filename, save_output = ...
if not filename then
	error("usage: wp --lua scripts/benchmark-large-text.lua FILE")
end

local function timed(label, callback)
	local start = wg.time()
	local result = {callback()}
	wg.printout(string.format("%-24s %.6f s\n", label, wg.time() - start))
	return table.unpack(result)
end

local buffer = assert(timed("mapped-file initialization", function()
	return wg.opentextbuffer(filename)
end))

wg.printout(string.format("logical size             %.0f bytes\n", buffer:size()))
timed("unchanged save", function()
	assert(buffer:save(filename))
end)
timed("first viewport", function()
	local newline = buffer:find(0, 10) or buffer:size()
	return buffer:slice(0, math.min(newline, 4096))
end)
timed("jump to 50 percent", function()
	local middle = math.floor(buffer:size() / 2)
	return buffer:find(middle, 10)
end)
timed("insert + delete", function()
	local middle = math.floor(buffer:size() / 2)
	buffer:insert(middle, "benchmark")
	buffer:delete(middle, 9)
end)
timed("undo + redo", function()
	buffer:undo()
	buffer:redo()
end)
timed("EOF enter + type + line", function()
	local eof = buffer:size()
	buffer:insert(eof, "\nx")
	assert(buffer:rfind(0, 10, buffer:size()) == eof)
	buffer:delete(eof, 2)
end)
if save_output then
	timed("atomic streaming save", function()
		assert(buffer:save(save_output))
	end)
end

local status = wg.readfile("/proc/self/status")
if status then
	local rss = status:match("VmRSS:%s*([^\n]+)")
	if rss then wg.printout("resident memory          "..rss.."\n") end
end
buffer:close()
