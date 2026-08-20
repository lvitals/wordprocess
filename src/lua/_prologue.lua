--!strict
-- © 2020 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

-- Global definitions that the various source files need.

Cmd = {}

BLINK_ON_TIME = 0.8
BLINK_OFF_TIME = 0.53
IDLE_TIME = (BLINK_ON_TIME + BLINK_OFF_TIME) * 5

-- Polyfills for Luau.

function loadfile(filename)
	local data, e = wg.readfile(filename)
	if data then
		return loadstring(data, filename)
	end
	return nil, e
end

