--!nonstrict
loadfile("tests/testsuite.lua")()

-- Keep the requested widths independent of the user's persisted first-line
-- indentation preference.
GlobalSettings.lookandfeel.firstlineindent = false
UpdateDocumentStyles()

-- This file exercises the plain character-counting fallback specifically,
-- so it must not pick up whichever real hyphenation pattern files (if any)
-- happen to be installed on the machine running the tests; that behaviour
-- is covered on its own, with synthetic pattern files, in tests/hyphenation.lua.
GlobalSettings.hyphenation = {filenames = {}}
ResetHyphenationPatternCache()

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
-- The remainder opens its own line ("leadingfragment") rather than a
-- standalone forced fragment, because further words may still follow it.
local continuation = balancedwrap.lines[2].leadingfragment
AssertEquals(4, continuation.start)
local continuationx = balanced:getXOffsetOfWord(2, continuation.start)
AssertEquals(-3, continuationx)

-- Reaching the wrap boundary must switch immediately to "letters-" plus a
-- continuation line; it must not first move the complete word and wait for
-- one further input before showing the hyphen (as long as the word is long
-- enough to leave at least two characters on each side of the hyphen).
local narrow = CreateParagraph("P", {"hello", "abcd"})
currentDocument[1] = narrow
currentDocument:wrap(9)
local narrowwrap = narrow:wrap(9)
AssertEquals(2, #narrowwrap.lines)
AssertNotNull(narrowwrap.lines[1].trailingfragment)
AssertEquals("ab", narrow[2]:sub(
	narrowwrap.lines[1].trailingfragment.start,
	narrowwrap.lines[1].trailingfragment.finish - 1))
AssertEquals(true, narrowwrap.lines[1].trailingfragment.hyphen)
AssertEquals(3, narrowwrap.lines[2].leadingfragment.start)

-- A word must never be hyphenated in a way that leaves a single orphan
-- letter dangling alone on its own line (e.g. "pode-" / "m"). When the word
-- is too short to leave at least two characters on both sides of the
-- hyphen, the whole word moves to a fresh line instead, exactly as it would
-- in non-hyphenating wrap mode.
local tooshort = CreateParagraph("P", {"hello", "ab"})
currentDocument[1] = tooshort
currentDocument:wrap(8)
local tooshortwrap = tooshort:wrap(8)
AssertEquals(2, #tooshortwrap.lines)
AssertEquals(nil, tooshortwrap.lines[1].trailingfragment)
AssertTableEquals({1}, tooshortwrap.lines[1])
AssertTableEquals({2}, tooshortwrap.lines[2])
AssertEquals(nil, tooshortwrap.lines[2].fragment)

-- Regression test for the reported bug: a five-letter word ("podem") that
-- would naively hyphenate as "pode-" / "m" must instead break with at least
-- two characters on each side, e.g. "pod-" / "em".
local podem = CreateParagraph("P", {"aaaa", "podem"})
currentDocument[1] = podem
currentDocument:wrap(10)
local podemwrap = podem:wrap(10)
AssertEquals(2, #podemwrap.lines)
AssertNotNull(podemwrap.lines[1].trailingfragment)
AssertEquals("pod", podem[2]:sub(
	podemwrap.lines[1].trailingfragment.start,
	podemwrap.lines[1].trailingfragment.finish - 1))
AssertEquals(true, podemwrap.lines[1].trailingfragment.hyphen)
AssertEquals("em", podem[2]:sub(
	podemwrap.lines[2].leadingfragment.start, #podem[2]))

-- A hyphenated word's remainder must share its line with whatever comes
-- next when there's room for it, instead of always claiming a line to
-- itself: regression test for the reported bug where "podem neste editor"
-- wrapped as "pod-" / "em" / "neste editor" (three lines) instead of
-- "pod-" / "em neste" / "editor" (two words correctly packed together).
local flowing = CreateParagraph("P", {"aaaa", "podem", "neste", "editor"})
currentDocument[1] = flowing
currentDocument:wrap(10)
local flowingwrap = flowing:wrap(10)
AssertEquals(3, #flowingwrap.lines)
AssertTableEquals({1, 2}, flowingwrap.lines[1])
AssertTableEquals({2, 3}, flowingwrap.lines[2])
AssertTableEquals({4}, flowingwrap.lines[3])
AssertNotNull(flowingwrap.lines[2].leadingfragment)
AssertEquals("em", flowing[2]:sub(
	flowingwrap.lines[2].leadingfragment.start, #flowing[2]))

-- Regression test for a rendering-position bug: the trailing fragment
-- ("pod-", still on line 1) and the leading fragment ("em", opening line 2)
-- are visual pieces of the very same word, but xs[] only has one slot per
-- word number. Writing xs[wn]=0 for the leading fragment used to clobber
-- the trailing fragment's real on-line position, drawing "pod-" at column 0
-- on top of "aaaa" instead of after it (e.g. "od-o" overlapping "algo" in
-- the reported document).
AssertEquals(5, flowingwrap.xs[2])
AssertEquals(5, flowing:getXOffsetOfWord(2, 1))
AssertEquals(-3, flowing:getXOffsetOfWord(2, 4))

-- The same orphan-avoidance rule applies when a single word is wider than an
-- entire fresh line (e.g. Page preview width with a long compound word) and
-- has to be split across several forced lines: the final fragment must not
-- be left with just one or two characters short of the minimum either. The
-- final fragment still opens a line of its own here because there is no
-- following word to share it with.
local wideword = CreateParagraph("P", {string.rep("x", 39)})
currentDocument[1] = wideword
currentDocument:wrap(20)
local widewordwrap = wideword:wrap(20)
AssertEquals(3, #widewordwrap.lines)
AssertEquals(true, widewordwrap.lines[1].fragment.hyphen)
AssertEquals(true, widewordwrap.lines[2].fragment.hyphen)
AssertNotNull(widewordwrap.lines[3].leadingfragment)
AssertEquals(2, widewordwrap.lines[3].leadingfragment.finish -
	widewordwrap.lines[3].leadingfragment.start)

-- Multi-byte UTF-8 letters must be measured in whole characters, not bytes,
-- both for sizing fragments and for finding where to move a hyphen back to
-- satisfy the minimum. Getting this wrong previously hung the editor by
-- landing a fragment boundary in the middle of an accented character's byte
-- sequence.
local accented = CreateParagraph("P", {"a", "responsabilização"})
currentDocument[1] = accented
currentDocument:wrap(19)
local accentedwrap = accented:wrap(19)
AssertEquals(2, #accentedwrap.lines)
AssertNotNull(accentedwrap.lines[1].trailingfragment)
AssertEquals(true, accentedwrap.lines[1].trailingfragment.hyphen)
AssertEquals("responsabilizaç", accented[2]:sub(
	accentedwrap.lines[1].trailingfragment.start,
	accentedwrap.lines[1].trailingfragment.finish - 1))
AssertEquals("ão", accented[2]:sub(
	accentedwrap.lines[2].leadingfragment.start, #accented[2]))

local wideaccented = CreateParagraph("P", {"responsabilização"})
currentDocument[1] = wideaccented
currentDocument:wrap(10)
local wideaccentedwrap = wideaccented:wrap(10)
AssertEquals(2, #wideaccentedwrap.lines)
AssertEquals(true, wideaccentedwrap.lines[1].fragment.hyphen)
AssertEquals("responsab", wideaccented[1]:sub(
	wideaccentedwrap.lines[1].fragment.start,
	wideaccentedwrap.lines[1].fragment.finish - 1))
AssertEquals("ilização", wideaccented[1]:sub(
	wideaccentedwrap.lines[2].leadingfragment.start, #wideaccented[1]))

-- A word and its adjacent sentence punctuation form one wrapping unit: the
-- punctuation always travels with whichever fragment holds the end of the
-- word, so it is never orphaned by a hyphenated split. When the whole unit
-- already fits in the room left on the line, prefer that untouched over
-- manufacturing a hyphen.
for _, punctuation in ipairs({",", ".", ";", ":", "!", "?"}) do
	local punctuated = CreateParagraph("P", {"hello", "closed"..punctuation})
	local punctuatedWrap = punctuated:wrap(8)
	AssertEquals(2, #punctuatedWrap.lines)
	AssertTableEquals({1}, punctuatedWrap.lines[1])
	AssertTableEquals({2}, punctuatedWrap.lines[2])
	AssertEquals(nil, punctuatedWrap.lines[1].trailingfragment)
	AssertEquals(nil, punctuatedWrap.lines[2].fragment)
end

local exactPunctuation = CreateParagraph("P", {"a", "closed,"})
local exactPunctuationWrap = exactPunctuation:wrap(9)
AssertEquals(1, #exactPunctuationWrap.lines)
AssertTableEquals({1, 2}, exactPunctuationWrap.lines[1])
AssertEquals(nil, exactPunctuationWrap.lines[1].trailingfragment)

-- Regression test for the reported bug: a punctuated word that does NOT fit
-- in the room left on the line, but is long enough to hyphenate cleanly
-- (respecting the usual two-characters-per-side minimum), must still be
-- hyphenated instead of always jumping whole to a fresh line just because
-- it would fit there too. The comma stays attached to the fragment that
-- holds the end of the word.
local punctuatedFlowing = CreateParagraph("P", {
	string.rep("a", 12), "documentos,"})
currentDocument[1] = punctuatedFlowing
currentDocument:wrap(17)
local punctuatedFlowingWrap = punctuatedFlowing:wrap(17)
AssertEquals(2, #punctuatedFlowingWrap.lines)
AssertNotNull(punctuatedFlowingWrap.lines[1].trailingfragment)
AssertEquals(true, punctuatedFlowingWrap.lines[1].trailingfragment.hyphen)
AssertEquals("doc", punctuatedFlowing[2]:sub(
	punctuatedFlowingWrap.lines[1].trailingfragment.start,
	punctuatedFlowingWrap.lines[1].trailingfragment.finish - 1))
AssertEquals("umentos,", punctuatedFlowing[2]:sub(
	punctuatedFlowingWrap.lines[2].leadingfragment.start, #punctuatedFlowing[2]))

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
