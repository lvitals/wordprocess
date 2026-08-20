--!nonstrict
loadfile("tests/testsuite.lua")()

GlobalSettings.lookandfeel.tabkeyenabled = true
GlobalSettings.lookandfeel.tabwidth = 4
Cmd.InsertStringIntoParagraph("a")
Cmd.InsertTab()
local markerword = currentDocument.cw - 1
AssertEquals(true, WordHasTabMarker(currentDocument[1][markerword]))
Cmd.InsertStringIntoParagraph("b")
AssertEquals("a    b", currentDocument[1]:asString())
AssertEquals(true, WordHasTabMarker(currentDocument[1][markerword]))

local spaces = CreateParagraph("P", {"a", "", "", "", "b"})
for _, word in ipairs(spaces) do
	AssertEquals(false, WordHasTabMarker(word))
end

GlobalSettings.lookandfeel.tabkeyenabled = false
AssertEquals(false, Cmd.InsertTab())
AssertEquals("a    b", currentDocument[1]:asString())
