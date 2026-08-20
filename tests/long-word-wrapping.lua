--!nonstrict
loadfile("tests/testsuite.lua")()

local para = currentDocument[1]
para[1] = "abcdefghijklmnopqrst"
currentDocument:wrap(8)

GlobalSettings.lookandfeel.wordwrapmode = "Move word"
para._wrapdata = nil
local wd = para:wrap(8)
AssertEquals(3, #wd.lines)
AssertEquals("abcdefgh", para[1]:sub(
	wd.lines[1].fragment.start, wd.lines[1].fragment.finish - 1))
AssertEquals(false, wd.lines[1].fragment.hyphen)
local line = para:getLineOfWord(1, 8)
AssertEquals(1, line)
line = para:getLineOfWord(1, 9)
AssertEquals(2, line)
line = para:getLineOfWord(1, #para[1] + 1)
AssertEquals(3, line)

GlobalSettings.lookandfeel.wordwrapmode = "Hyphenate"
para._wrapdata = nil
wd = para:wrap(8)
AssertEquals(3, #wd.lines)
AssertEquals("abcdefg", para[1]:sub(
	wd.lines[1].fragment.start, wd.lines[1].fragment.finish - 1))
AssertEquals(true, wd.lines[1].fragment.hyphen)
line = para:getLineOfWord(1, 7)
AssertEquals(1, line)
line = para:getLineOfWord(1, 8)
AssertEquals(2, line)
line = para:getLineOfWord(1, #para[1] + 1)
AssertEquals(3, line)

-- Hyphenation also uses the remaining room at the end of a partially filled
-- line, instead of moving the whole word and leaving a ragged right edge.
local balanced = CreateParagraph("P", {"hello", "abcdef"})
currentDocument[1] = balanced
currentDocument:wrap(10)
GlobalSettings.lookandfeel.wordwrapmode = "Hyphenate"
local balancedwrap = balanced:wrap(10)
AssertEquals(2, #balancedwrap.lines)
AssertNotNull(balancedwrap.lines[1].trailingfragment)
AssertEquals(true, balancedwrap.lines[1].trailingfragment.hyphen)
AssertEquals("abc", balanced[2]:sub(
	balancedwrap.lines[1].trailingfragment.start,
	balancedwrap.lines[1].trailingfragment.finish - 1))
local continuation = balancedwrap.lines[2].fragment
AssertEquals(4, continuation.start)
local continuationx = balanced:getXOffsetOfWord(2, continuation.start)
AssertEquals(-3, continuationx)

-- Even when only two columns remain, reaching that boundary must switch
-- immediately to "letter-" plus a continuation line; it must not first move
-- the complete word and wait for one further input before showing the hyphen.
local narrow = CreateParagraph("P", {"hello", "ab"})
currentDocument[1] = narrow
currentDocument:wrap(8)
local narrowwrap = narrow:wrap(8)
AssertEquals(2, #narrowwrap.lines)
AssertNotNull(narrowwrap.lines[1].trailingfragment)
AssertEquals("a", narrow[2]:sub(
	narrowwrap.lines[1].trailingfragment.start,
	narrowwrap.lines[1].trailingfragment.finish - 1))
AssertEquals(true, narrowwrap.lines[1].trailingfragment.hyphen)
AssertEquals(2, narrowwrap.lines[2].fragment.start)

-- Wrapping is visual only: the stored/exported text remains unchanged.
AssertEquals("hello abcdef", balanced:asString())

-- Vertical navigation must distinguish the visual fragments even though
-- they all belong to the same stored word.
currentDocument[1] = para
currentDocument:wrap(8)
GlobalSettings.lookandfeel.wordwrapmode = "Move word"
para._wrapdata = nil
currentDocument.cw = 1
currentDocument.co = 4
AssertEquals(true, Cmd.GotoNextLine())
AssertEquals(12, currentDocument.co)
AssertEquals(true, Cmd.GotoNextLine())
AssertEquals(20, currentDocument.co)
AssertEquals(true, Cmd.GotoPreviousLine())
AssertEquals(12, currentDocument.co)
