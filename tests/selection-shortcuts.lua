--!nonstrict
loadfile("tests/testsuite.lua")()

Cmd.InsertStringIntoParagraph("one two")
Cmd.SplitCurrentParagraph()
Cmd.InsertStringIntoParagraph("three four")

AssertEquals("Select all", GetShortcutActionLabel("^A"))
AssertEquals(true, Cmd.SelectAll())
local mp, mw, mo, cp, cw, co = currentDocument:getMarks()
AssertEquals(1, mp)
AssertEquals(1, mw)
AssertEquals(1, mo)
AssertEquals(2, cp)
AssertEquals(#currentDocument[2], cw)
AssertEquals(#currentDocument[2][cw] + 1, co)

AssertEquals(true, Cmd.Copy())
AssertEquals(2, #GetClipboard())
AssertEquals("one two", GetClipboard()[1]:asString())
AssertEquals("three four", GetClipboard()[2]:asString())

AssertEquals(true, Cmd.SelectAll())
AssertEquals(true, Cmd.Delete())
AssertEquals(1, #currentDocument)
AssertEquals("", currentDocument[1]:asString())
