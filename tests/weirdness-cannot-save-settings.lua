--!nonstrict
loadfile("tests/testsuite.lua")()

local filename = wg.mkdtemp().."/testfile"

GlobalSettings = {
	intValue = 1,
	stringValue = "one",
	floatValue = 1.0,
	tableValue = { 1, 2, 3, foo="bar" }
}
FireEvent("RegisterAddons")

SaveGlobalSettings(filename)

local want = GlobalSettings
GlobalSettings = {}

LoadGlobalSettings(filename)

AssertTableAndPropertiesEquals(want, GlobalSettings)

-- An interrupted or otherwise incomplete settings save must not prevent the
-- application from starting.
GlobalSettings = {}
local emptyFilename = wg.mkdtemp().."/empty-settings.dat"
local _, writeError = wg.writefile(emptyFilename, "")
AssertEquals(nil, writeError)
LoadGlobalSettings(emptyFilename)
AssertTableAndPropertiesEquals({}, GlobalSettings)
