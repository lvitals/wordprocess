--!nonstrict
loadfile("tests/testsuite.lua")()

GlobalSettings.lookandfeel.tabkeyenabled = true
GlobalSettings.lookandfeel.tabwidth = 2
Cmd.InsertStringIntoParagraph("one")
Cmd.InsertTab()
local firsttab = currentDocument.cw - 1
Cmd.InsertStringIntoParagraph("two")
Cmd.InsertTab()
local secondtab = currentDocument.cw - 1
Cmd.InsertStringIntoParagraph("three")

Cmd.GotoBeginningOfDocument()
AssertEquals(true, Cmd.GotoNextTab())
AssertEquals(firsttab, currentDocument.cw)
AssertEquals(true, Cmd.GotoNextTab())
AssertEquals(secondtab, currentDocument.cw)
AssertEquals(true, Cmd.GotoPreviousTab())
AssertEquals(firsttab, currentDocument.cw)

Cmd.SplitCurrentParagraph()
AssertEquals(2, #currentDocument)
Cmd.DeleteCurrentParagraph()
AssertEquals(1, #currentDocument)

local found_h = false
for _, entry in ipairs(GetCommandLayerBindings()) do
	if entry.key == "H" then
		AssertEquals("ZL", entry.binding)
		found_h = true
	end
end
AssertEquals(true, found_h)
OverrideKey("COMMAND_H", "ZR")
AssertEquals("Cursor right", GetShortcutActionLabel("COMMAND_H"))

NavigationMode = false
Cmd.ToggleNavigationMode()
AssertEquals(true, NavigationMode)
Cmd.ToggleNavigationMode()
AssertEquals(false, NavigationMode)
AssertEquals("Toggle navigation mode", GetShortcutActionLabel("AN"))
