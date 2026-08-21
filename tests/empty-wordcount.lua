--!nonstrict
loadfile("tests/testsuite.lua")()

-- A blank document contains a compatibility paragraph/caret position, but no
-- lexical words. The status bar must never count that placeholder as a word.
AssertEquals(0, currentDocument.wordcount)
local terms = {}
FireEvent("BuildStatusBar", terms)
local values = {}
for _, term in ipairs(terms) do values[#values+1] = term.value end
local status = table.concat(values, " | ")
AssertEquals(true, status:find("0 words", 1, true) ~= nil)
AssertEquals(nil, status:find("1 word", 1, true))

Cmd.InsertStringIntoParagraph("hello")
currentDocument:renumber()
AssertEquals(1, currentDocument.wordcount)
