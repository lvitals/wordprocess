--!nonstrict
-- © 2015 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

GlobalSettings = {}

local filename = CONFIGDIR.."/settings.dat"

function LoadGlobalSettings(f)
	if not f then
		f = filename
	end
	assert(f)

	local s = LoadFromFile(f)
	if s then
		if s.globalSettings then
			GlobalSettings = s.globalSettings
		else
			-- Backwards compatibility.
			GlobalSettings = s
		end

		FireEvent("RegisterAddons")
	end
end

function SaveGlobalSettings(f)
	if not f then
		f = filename
	end
	assert(f)

	local r, e = SaveToFile(
		f,
		{globalSettings=GlobalSettings}
	)
	return r
end

