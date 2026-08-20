--!nonstrict
loadfile("tests/testsuite.lua")()

wg.getscreensize = function() return 60, 12 end
for i = 1, 100 do
	currentDocument:appendParagraph(CreateParagraph("P", {"line "..i}))
end

ResizeScreen()
RedrawScreen()
local firstbottom = currentDocument._botp
AssertEquals(true, Cmd.GotoNextPage())
if currentDocument.cp <= firstbottom then
	error("page down did not move beyond the previous viewport")
end

RedrawScreen()
local secondposition = currentDocument.cp
AssertEquals(true, Cmd.GotoNextPage())
if currentDocument.cp <= secondposition then
	error("repeated page down did not make progress")
end

RedrawScreen()
local oldtop = currentDocument._topp
AssertEquals(true, Cmd.GotoPreviousPage())
if currentDocument.cp >= oldtop then
	error("page up did not move beyond the previous viewport")
end
