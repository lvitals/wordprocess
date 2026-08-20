-- © 2023 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local function instantiate(self, impl)
	return setmetatable(impl or {}, {__index = self, __call = instantiate})
end

Object = {}
setmetatable(Object, {__call = instantiate})

