--!nonstrict
loadfile("tests/testsuite.lua")()

ScreenWidth = 80
currentDocument:wrap(ScreenWidth)

-- Test 1: Multiple paragraphs, moving down at bottom of document
Cmd.InsertStringIntoParagraph("first line of text")
Cmd.SplitCurrentParagraph()
Cmd.InsertStringIntoParagraph("second line of text")
Cmd.GotoBeginningOfDocument()

-- Move to column 6 on line 1
for i=1,5 do Cmd.GotoNextChar() end
AssertTableEquals({1, 1, 6}, {currentDocument.cp, currentDocument.cw, currentDocument.co})

-- Move down to line 2
Cmd.GotoNextLine()
AssertTableEquals({2, 1, 6}, {currentDocument.cp, currentDocument.cw, currentDocument.co})

-- Move down again on line 2 (last line) -> should stay on line 2, col 6 (not jump to end of line)
Cmd.GotoNextLine()
AssertTableEquals({2, 1, 6}, {currentDocument.cp, currentDocument.cw, currentDocument.co})

-- Test 2: Moving up at top of document
Cmd.GotoBeginningOfDocument()
for i=1,5 do Cmd.GotoNextChar() end
AssertTableEquals({1, 1, 6}, {currentDocument.cp, currentDocument.cw, currentDocument.co})

-- Move up at line 1 (first line) -> should stay on line 1, col 6 (not jump to beginning of line)
Cmd.GotoPreviousLine()
AssertTableEquals({1, 1, 6}, {currentDocument.cp, currentDocument.cw, currentDocument.co})

-- Test 3: Wrapped single paragraph
while #currentDocument > 1 do
	currentDocument:deleteParagraphAt(2)
end
currentDocument[1] = CreateParagraph("P", "")
currentDocument.cp = 1
currentDocument.cw = 1
currentDocument.co = 1

ScreenWidth = 20
currentDocument:wrap(ScreenWidth)

Cmd.InsertStringIntoParagraph("one two three four five six seven eight nine ten")
currentDocument:wrap(ScreenWidth)

local lines = currentDocument[1]:wrap().lines
assert(#lines > 1, "Expected multiple wrapped lines")

-- Go to line 1
Cmd.GotoBeginningOfDocument()
for i=1,5 do Cmd.GotoNextChar() end
local cp1, cw1, co1 = currentDocument.cp, currentDocument.cw, currentDocument.co

-- Up at top line -> should stay
Cmd.GotoPreviousLine()
AssertTableEquals({cp1, cw1, co1}, {currentDocument.cp, currentDocument.cw, currentDocument.co})

-- Go down to last wrapped line
for i=1,#lines-1 do
	Cmd.GotoNextLine()
end
local last_cp, last_cw, last_co = currentDocument.cp, currentDocument.cw, currentDocument.co

-- Down on last wrapped line -> should stay on same column, NOT jump to end of paragraph
Cmd.GotoNextLine()
AssertTableEquals({last_cp, last_cw, last_co}, {currentDocument.cp, currentDocument.cw, currentDocument.co})
