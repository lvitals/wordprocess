--!nonstrict
loadfile("tests/testsuite.lua")()

-- Margin display mode (Style -> Set margin mode) is a global editor
-- preference stored in settings.dat (GlobalSettings.lookandfeel.marginmode),
-- not document content -- see SetDefaultMarginMode/GetDefaultMarginMode in
-- src/lua/addons/look-and-feel.lua and the "DocumentLoaded" listener in
-- src/lua/margin.lua. This must hold across three situations: creating a
-- new document, restarting the application (settings.dat reloaded from
-- disk), and loading a document that was saved under a *different* mode in
-- a previous session.

-- 1. Choosing a margin mode persists it as the default for documents
-- created from here on.
SetMarginMode(3) -- paragraph numbers
AssertEquals(3, GlobalSettings.lookandfeel.marginmode)

local fresh = CreateDocument()
AssertEquals(3, fresh.viewmode)
if fresh.margin <= 0 then
	error("expected a freshly created document to reserve a margin for mode 3")
end

-- 2. The preference survives a save/reload of settings.dat, independently
-- of any document -- i.e. it would still be mode 3 after restarting the
-- application.
local settingsfile = wg.mkdtemp().."/settings.dat"
SaveGlobalSettings(settingsfile)
GlobalSettings = {}
LoadGlobalSettings(settingsfile)
FireEvent("RegisterAddons")

AssertEquals(3, GetDefaultMarginMode())
AssertEquals(3, CreateDocument().viewmode)

-- 3. A document saved under a *different* mode in a previous session must
-- not let its serialized viewmode override the current global preference
-- on load.
documentSet:clean() -- avoid the "unsaved changes?" confirmation prompt
currentDocument.viewmode = 1
currentDocument.margin = 0

local docfile = wg.mkdtemp().."/oldmode.wp"
AssertEquals(true, SaveDocumentSetRaw(docfile))

GlobalSettings.lookandfeel.marginmode = 1
documentSet:clean()
AssertEquals(true, Cmd.LoadDocumentSet(docfile))
AssertEquals(1, currentDocument.viewmode)

GlobalSettings.lookandfeel.marginmode = 3
documentSet:clean()
AssertEquals(true, Cmd.LoadDocumentSet(docfile))
AssertEquals(3, currentDocument.viewmode)
if currentDocument.margin <= 0 then
	error("expected the loaded document to reserve a margin for mode 3, not keep the file's saved margin of 0")
end
