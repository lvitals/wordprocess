--!nonstrict
loadfile("tests/testsuite.lua")()

local tmpfile = wg.mkdtemp().."/testfile"

local t = {
	foo = {
		bar = {
			n = 1,
			s = "one"
		}
	},
	array = { "one", "two", "three" }
}

local r, e = SaveToFile(tmpfile, {data = t})
AssertEquals(nil, e)

local tt, e = LoadFromFile(tmpfile)
AssertEquals(nil, e)
AssertTableEquals(t, tt.data)

-- A native file contains documents, not the saving editor's session state.
local documentFilename = wg.mkdtemp().."/document.wp"
local native = CreateDocumentSet()
native.menu = CreateMenuTree()
native.menu.accelerators.TEST = "editor-only"
native.statusbar = false
native.name = "/machine-specific/path/document.wp"
native.findtext = "private search"
native.replacetext = "private replacement"
native.addons.example = {enabled=true}
native:addDocument(CreateDocument(), "main")
native.current.pageLayout = {profile="Test", pageWidthCm=21}
AssertEquals(true, SaveToFile(documentFilename, native))

local nativeBytes = assert(wg.readfile(documentFilename))
AssertEquals(nil, nativeBytes:find(".menu.", 1, true))
AssertEquals(nil, nativeBytes:find("\n.statusbar:", 1, true))
AssertEquals(nil, nativeBytes:find("\n.name:", 1, true))
AssertEquals(nil, nativeBytes:find("\n.findtext:", 1, true))
AssertEquals(nil, nativeBytes:find("\n.replacetext:", 1, true))
AssertEquals(true, nativeBytes:find(".addons.example.enabled: true", 1, true) ~= nil)
AssertEquals(true, nativeBytes:find(".documents.1.pageLayout.profile: \"Test\"", 1, true) ~= nil)

-- Old files remain readable without importing their editor preferences.
local legacy = nativeBytes:gsub("WordProcess document v1\n",
	"WordProcess document v1\n.statusbar: false\n"..
	".name: \"/old/machine.wp\"\n.menu.accelerators.TEST: \"legacy\"\n", 1)
local loadedLegacy = assert(LoadFromString("legacy.wp", legacy))
AssertEquals(true, loadedLegacy.statusbar)
AssertEquals(nil, loadedLegacy.name)
AssertEquals(nil, loadedLegacy.menu.accelerators.TEST)
AssertEquals("Test", loadedLegacy.current.pageLayout.profile)
