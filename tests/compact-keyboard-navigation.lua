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
AssertEquals("Keyboard shortcuts...", GetShortcutActionLabel("A?"))
AssertEquals("Unbound", GetShortcutActionLabel("AH"))
AssertEquals("Cursor left", GetShortcutActionLabel("A^H"))
AssertEquals("Cursor down", GetShortcutActionLabel("A^J"))
AssertEquals("Cursor up", GetShortcutActionLabel("A^K"))
AssertEquals("Cursor right", GetShortcutActionLabel("A^L"))
AssertEquals("Goto previous tabulation", GetShortcutActionLabel("A^I"))
AssertEquals("Goto next tabulation", GetShortcutActionLabel("A^O"))
AssertEquals("Delete current paragraph", GetShortcutActionLabel("AS^D"))

local ok, err = pcall(function()
	CreateMenu("Conflicting test menu", {
		{id="TEST_RESERVED_MENU_KEY", mk="H", label="Reserved", fn=function() end},
	})
end)
AssertEquals(false, ok)
AssertEquals(true, err:find("reserved for H/J/K/L navigation", 1, true) ~= nil)

local checkbox = Form.Checkbox {value=true, draw=function() end}
checkbox["h"](checkbox, "h")
AssertEquals(false, checkbox.value)
checkbox["l"](checkbox, "l")
AssertEquals(true, checkbox.value)

local toggle = Form.Toggle {
	values={"one", "two", "three"}, value=2, draw=function() end,
}
toggle["h"](toggle, "h")
AssertEquals(1, toggle.value)
toggle["l"](toggle, "l")
AssertEquals(2, toggle.value)
AssertEquals(true, Form.TextField {value=""}.accepts_text)

local numeric = Form.TextField {
	value="123", numeric=true, cursor=2, draw=function() end,
}
numeric["h"](numeric, "h")
AssertEquals(1, numeric.cursor)
numeric["l"](numeric, "l")
AssertEquals(2, numeric.cursor)
AssertEquals("123", numeric.value)
numeric:key("x")
AssertEquals("123", numeric.value)

local textual = Form.TextField {
	value="ab", cursor=2, draw=function() end,
}
textual["h"](textual, "h")
AssertEquals("ahb", textual.value)

NavigationMode = false
Cmd.ToggleNavigationMode()
AssertEquals(true, NavigationMode)
Cmd.ToggleNavigationMode()
AssertEquals(false, NavigationMode)
AssertEquals("Toggle navigation mode", GetShortcutActionLabel("AN"))
