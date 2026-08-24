--!nonstrict
loadfile("tests/testsuite.lua")()

-- Regression test: ResizeScreen's comment for the margin-annotation case
-- ("But if a widescreen maximum-width cap actually leaves room to spare,
-- still center the (narrower) paper within it, same as with no margin
-- active") was never actually implemented for the default "Fixed" scroll
-- mode -- that branch unconditionally pinned the paper to the minimum
-- gutter width instead. So with a paragraph-number/line-number margin
-- active (currentDocument.margin > 0) and an editor width mode that caps
-- the paper narrower than the screen ("Column limit" or "Page preview"),
-- the paper stayed jammed against the left edge instead of being centered
-- like it is with no margin. See src/lua/redraw.lua's ResizeScreen().

wg.getscreensize = function() return 100, 20 end
AssertEquals("Fixed", GetScrollMode())

local usablewidth = 100 - 2 -- SCROLLBAR_WIDTH + SCROLLBAR_GUTTER, see redraw.lua

-- Column limit: an explicit width cap well inside the 98-column usable
-- width, leaving plenty of room to center the paper (plus its margin
-- gutter) instead of pinning it to the left.
GlobalSettings.lookandfeel.widthmode = "Column limit"
GlobalSettings.lookandfeel.maxwidth = 40
currentDocument.margin = 3
ResizeScreen()
local margin, width = GetPaperLayout()
AssertEquals(40, width)
AssertEquals(math.floor((usablewidth - width) / 2), margin)
if margin <= currentDocument.margin + 2 then
	error(string.format(
		"Column limit: papermargin=%d is pinned to the minimum gutter " ..
		"instead of centered", margin))
end

-- Page preview: same expectation, capped by the document's own page width
-- instead of an explicit column count.
GlobalSettings.lookandfeel.widthmode = "Page preview"
currentDocument.margin = 3
ResizeScreen()
margin, width = GetPaperLayout()
AssertEquals(math.floor((usablewidth - width) / 2), margin)
if margin <= currentDocument.margin + 2 then
	error(string.format(
		"Page preview: papermargin=%d is pinned to the minimum gutter " ..
		"instead of centered", margin))
end

-- Full width (no cap): nothing narrower than the screen constrains the
-- paper, so there's no slack to center into -- the gutter should stay
-- pinned to its minimum and the paper should fill the rest of the row,
-- exactly as before this fix, rather than leaving a wide, pointless strip
-- of blank space mirrored on the left.
GlobalSettings.lookandfeel.widthmode = "Full width"
currentDocument.margin = 3
ResizeScreen()
margin, width = GetPaperLayout()
AssertEquals(currentDocument.margin + 2, margin)
AssertEquals(usablewidth - margin, width)

-- No margin active at all: unaffected by any of this.
currentDocument.margin = 0
GlobalSettings.lookandfeel.widthmode = "Column limit"
GlobalSettings.lookandfeel.maxwidth = 40
ResizeScreen()
margin, width = GetPaperLayout()
AssertEquals(40, width)
AssertEquals(math.floor(usablewidth / 2 - width / 2), margin)
