-- Benchmarks the native mapped piece-table backend without modifying the
-- source. Usage: wp --lua scripts/benchmark-large-text.lua FILE

local filename, save_output, random_edit_count = ...
if not filename then
	error("usage: wp --lua scripts/benchmark-large-text.lua FILE")
end
if save_output == "" then save_output = nil end

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
random_edit_count = tonumber(random_edit_count)
if random_edit_count and random_edit_count > 0 then
	local samples = {}
	local state = 1
	for i = 1, random_edit_count do
		state = (state * 1103515245 + 12345) % 2147483648
		local position = state % (buffer:size() + 1)
		local started = wg.time()
		buffer:insert(position, "x")
		state = (state * 1103515245 + 12345) % 2147483648
		local deletion = state % buffer:size()
		buffer:delete(deletion, 1)
		samples[i] = wg.time() - started
	end
	table.sort(samples)
	local median = samples[math.max(1, math.floor(#samples * 0.50))]
	local p99 = samples[math.max(1, math.floor(#samples * 0.99))]
	wg.printout(string.format("random edits            %d\n", random_edit_count))
	wg.printout(string.format("piece count             %.0f\n", buffer:piececount()))
	wg.printout(string.format("median edit latency     %.9f s\n", median))
	wg.printout(string.format("p99 edit latency        %.9f s\n", p99))
end
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
