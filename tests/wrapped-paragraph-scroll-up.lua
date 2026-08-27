--!nonstrict
loadfile("tests/testsuite.lua")()

-- Regression test: in Fixed scroll mode, moving the cursor up out of the
-- top of the viewport used to fall back to counting rows from the very
-- start of the document and pinning the cursor to the *bottom* row --
-- correct for scrolling past the end of the viewport, but the wrong
-- direction here, turning "scroll up one line" into a jump of a whole
-- viewport height. That fallback triggered not just when crossing into an
-- earlier paragraph, but also when moving to an earlier line *within* a
-- paragraph long enough to wrap across many screen rows -- which is the
-- case this test exercises. See src/lua/redraw.lua's cursor_before_top
-- handling next to rowoffsetfromtop().

wg.getscreensize = function() return 60, 20 end

local words = {}
for i = 1, 400 do
	words[#words + 1] = "word" .. tostring(i)
end
currentDocument[1] = CreateParagraph("P", words)

ResizeScreen()

-- Move deep into the paragraph, well past the first screenful, and let a
-- viewport get established there.
currentDocument.cw = 200
RedrawScreen()

local initial = currentDocument._topw
if not initial or initial <= 1 then
	error("test setup: expected the viewport to already be scrolled into the paragraph")
end

-- Step "up" one word at a time. As long as the cursor is still inside the
-- established viewport, the top must not move at all; once it steps
-- outside, the top must move by *one line's worth* of words, never jump
-- back towards the start of the paragraph.
local before = initial
for step = 1, 150 do
	currentDocument.cw = currentDocument.cw - 1
	RedrawScreen()

	local after = currentDocument._topw
	if after < before then
		local shrank = before - after
		-- One wrapped line in a ~60-column window holds a handful of
		-- "wordN" tokens -- generously bound it well below a jump back
		-- towards the start of a 400-word paragraph (the bug's symptom)
		-- without hard-coding the exact wrap width.
		if shrank > 20 then
			error(string.format(
				"expected the viewport top to move by about one line " ..
				"(a handful of words), not jump from word %d to word %d",
				before, after))
		end
	end
	before = after
end

-- 150 backward steps from word 200 must have made real, steady progress
-- towards the start of the paragraph -- not stalled (stuck re-jumping to
-- the same spot) and not overshot past word 1.
if (before > initial - 30) or (before < 1) then
	error(string.format(
		"expected the viewport top to have moved steadily from word %d " ..
		"down to somewhere well below it after 150 steps up; got word %d",
		initial, before))
end
