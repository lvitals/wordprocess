--!nonstrict
loadfile("tests/testsuite.lua")()

-- Regression test: in Fixed scroll mode (the default), once the cursor is
-- past the first screenful, RedrawScreen used to recompute its screen row
-- from the document start on every redraw and clamp it to the bottom row
-- whenever it didn't fit -- which pins whatever paragraph the cursor is on
-- to the very last visible line, no matter how it got there. That meant
-- moving the cursor to any other paragraph, even one already fully
-- visible on screen (e.g. clicking a few lines above where you'd been
-- typing), yanked the whole page to make the clicked line the new bottom
-- row instead of just leaving the cursor there. See src/lua/redraw.lua's
-- rowoffsetfromtop().

wg.getscreensize = function() return 60, 20 end

for i = 1, 200 do
	currentDocument:appendParagraph(CreateParagraph("P", {"line " .. i}))
end

-- Position the cursor near the end of the document (well past page one)
-- and redraw once, establishing a viewport pinned around it.
currentDocument.cp = 190
currentDocument.cw = 1
ResizeScreen()
RedrawScreen()

local topp, botp = currentDocument._topp, currentDocument._botp
if not topp or not botp or (botp - topp < 1) then
	error("expected a multi-line viewport before the click")
end

-- Click a line that's already inside that viewport: the view must not
-- move.
local clicktarget = topp + 2
if clicktarget >= botp then
	error("test setup: clicktarget must be strictly inside the viewport")
end

currentDocument.cp = clicktarget
currentDocument.cw = 1
RedrawScreen()

AssertEquals(topp, currentDocument._topp)
AssertEquals(botp, currentDocument._botp)

-- Sanity check the opposite case still works: jumping somewhere genuinely
-- off-screen (the very start of the document) must still scroll there.
currentDocument.cp = 1
currentDocument.cw = 1
RedrawScreen()

AssertEquals(1, currentDocument._topp)
if currentDocument._botp >= topp then
	error("expected jumping to the start of the document to actually scroll there")
end
