--!nonstrict
loadfile("tests/testsuite.lua")()

-- Regression test: in a mapped/large (text-buffer) document, only explicit
-- navigation commands (arrows, Goto, search, page up/down) kept _texttop in
-- sync with the cursor as they moved it. Backspace/Delete joining lines
-- across a line boundary -- e.g. holding Backspace to delete several lines
-- in a row -- moves the cursor the same way but through
-- deleteTextRange/previousTextPosition, which never touched _texttop. Once
-- the cursor's line drifted above the top of the last-drawn viewport, the
-- screen stopped scrolling: it kept showing the old, now-unrelated lines,
-- while the terminal cursor sat pinned to the top row of that frozen text.
-- Each further Backspace still deleted the correct (previous) character in
-- the document, but visually looked like it was eating characters ahead of
-- the cursor, because the row the blinking cursor sat on kept getting
-- redrawn with different, unrelated bytes as edits shifted the buffer under
-- the stale offset. See Document.ensureTextCursorVisible in document.lua.

wg.getscreensize = function() return 60, 20 end

local dir = wg.mkdtemp()
local source = dir.."/source.txt"
local lines = {}
local offsets = {}
local cum = 0
for i = 1, 60 do
	offsets[i] = cum
	local l = "line " .. i
	lines[#lines + 1] = l
	cum = cum + #l + 1
end
wg.writefile(source, table.concat(lines, "\n").."\n")

local document = assert(CreateTextBufferDocument(source))
currentDocument = document
documentSet:addDocument(document, "big")
ResizeScreen()

-- Position the cursor at the start of line 50, with the viewport already
-- scrolled so its top is line 40 -- as if the user had scrolled down mid
-- document, same as fixed-mode-click-preserves-viewport.lua does for the
-- paragraph-based engine.
document._textpos = offsets[50]
document._texttop = offsets[40]
RedrawScreen()

-- Repeatedly join with the previous line (holding Backspace at the start of
-- a line deletes lines one at a time, walking the cursor upward through the
-- document). After every redraw, the cursor's own line must never be above
-- the viewport's top line -- otherwise the screen has stopped following it.
for i = 1, 110 do
	AssertEquals(true, Cmd.DeleteSelectionOrPreviousChar())
	RedrawScreen()
	local linestart = document:textLineBounds()
	local top = document._texttop or 0
	if linestart < top then
		error(string.format(
			"backspace %d: cursor's line (offset %d) scrolled above the " ..
			"viewport top (offset %d) -- the screen stopped following the cursor",
			i, linestart, top))
	end
end

-- Sanity: the deletions actually landed on the intended text. 110
-- Backspaces from offset 383 (the start of line 50) remove exactly the 110
-- bytes immediately before the cursor -- offsets [273, 383) -- leaving the
-- rest of the document, before and after that gap, untouched.
local remaining = document._textbuffer:slice(0, document._textbuffer:size())
local original = table.concat(lines, "\n").."\n"
local expected = original:sub(1, 273)..original:sub(384)
AssertEquals(expected, remaining)
AssertEquals(273, document._textpos)

-- Same check in the other direction: typing enough newlines to run past the
-- bottom of the viewport must scroll it down to keep the cursor visible.
local down = assert(CreateTextBufferDocument(source))
currentDocument = down
documentSet:addDocument(down, "big2")
down._textpos = 0
down._texttop = 0
RedrawScreen()

for i = 1, 40 do
	AssertEquals(true, Cmd.SplitCurrentParagraph())
	RedrawScreen()
	local linestart = down:textLineBounds()
	local top = down._texttop or 0
	if linestart < top then
		error(string.format(
			"newline %d: cursor's line (offset %d) is above the viewport top " ..
			"(offset %d)", i, linestart, top))
	end
end
