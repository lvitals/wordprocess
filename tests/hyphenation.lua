--!nonstrict
loadfile("tests/testsuite.lua")()

-- Discovery mirrors the spelling-dictionary directory scan, restricted to
-- the "hyph_LL.dic" / "hyph-LL.dic" naming convention every hyphen-* system
-- package and LibreOffice/Firefox dictionary extension uses for this exact
-- pattern-file format, so an unrelated *.dic (e.g. a Hunspell spelling
-- dictionary) is never picked up by accident.
local discoveryDir = wg.mkdtemp()
AssertEquals(nil, select(2, wg.writefile(discoveryDir.."/hyph_en_US.dic", "UTF-8\n")))
AssertEquals(nil, select(2, wg.writefile(discoveryDir.."/hyph-pt-BR.dic", "UTF-8\n")))
AssertEquals(nil, select(2, wg.writefile(discoveryDir.."/en_US.dic", "not hyphenation data\n")))
AssertEquals(nil, select(2, wg.writefile(discoveryDir.."/notes.txt", "irrelevant\n")))
AssertTableEquals({
	discoveryDir.."/hyph-pt-BR.dic",
	discoveryDir.."/hyph_en_US.dic",
}, DiscoverHyphenationPatterns(discoveryDir))

local function withpatterns(content)
	local dir = wg.mkdtemp()
	local path = dir.."/hyph_test.dic"
	AssertEquals(nil, select(2, wg.writefile(path, content)))
	GlobalSettings.hyphenation = {filenames = {path}}
	ResetHyphenationPatternCache()
end

-- Basic case: a single pattern permits exactly one interior break.
withpatterns("UTF-8\na1b\n")
AssertTableEquals({3}, GetHyphenationPoints("xaby"))
-- Unrelated words are simply not recognised -- not an error, just no
-- pattern-driven points (callers fall back to their own default).
AssertTableEquals({}, GetHyphenationPoints("zzzz"))

-- Liang's algorithm keeps the *highest* value seen at each gap, regardless
-- of which pattern (or how long a substring) produced it: a longer match
-- ("vwx", started one character earlier) and a shorter one ("wx") can both
-- land on the very same gap (between 'w' and 'x'); a smaller odd value
-- from one must not overturn a larger even (forbidding) value from the
-- other.
withpatterns("UTF-8\nw2x\nvw1x\n")
AssertTableEquals({}, GetHyphenationPoints("vwxy"))

-- The reverse: a larger *odd* value must survive over a smaller even one
-- landing on the same gap.
withpatterns("UTF-8\nw3x\nvw2x\n")
AssertTableEquals({3}, GetHyphenationPoints("vwxy"))

-- The word-boundary marker ('.') anchors a pattern to a specific edge of
-- the word, the same way TeX/libhyphen patterns use it: ".ab" only matches
-- a word that actually *starts* with "ab", not an "ab" occurring later in
-- some other word -- plain substring matching alone couldn't tell those
-- apart.
withpatterns("UTF-8\n.a1b\n")
AssertTableEquals({2}, GetHyphenationPoints("abc"))
AssertTableEquals({}, GetHyphenationPoints("xab"))

-- ISO-8859-1 (the encoding real hyph_*.dic files for English, Portuguese,
-- French, German, Spanish, Italian and Dutch are actually shipped in) is
-- converted to UTF-8 on load, so accented pattern letters still match
-- multi-byte characters in the word correctly.
withpatterns("ISO8859-1\n"..string.char(0xE1).."1b\n")
AssertTableEquals({4}, GetHyphenationPoints("xáby"))
AssertEquals("xá", ("xáby"):sub(1, 3))
AssertEquals("by", ("xáby"):sub(4))

-- An unsupported/unrecognised encoding declaration is skipped rather than
-- silently producing corrupted (mis-decoded) patterns.
withpatterns("WINDOWS-1251\na1b\n")
AssertTableEquals({}, GetHyphenationPoints("xaby"))

-----------------------------------------------------------------------------
-- Integration with Paragraph.wrap: a real syllable boundary (from selected
-- pattern files) is preferred over the widest character cut that merely
-- fits, and the existing minimum-two-characters and orphan-avoidance rules
-- still apply on top of it.

GlobalSettings.lookandfeel.wordwrapmode = "Hyphenate"
GlobalSettings.lookandfeel.firstlineindent = false
UpdateDocumentStyles()
documentStyles["P"].indent = 0
documentStyles["P"].firstindent = nil

-- Only one pattern is defined, allowing a break between 'c' and 'd'; a
-- character-counting cut alone would have taken six characters ("abcdef-").
withpatterns("UTF-8\nc1d\n")
local guided = CreateParagraph("P", {"xx", "abcdefgh"})
currentDocument[1] = guided
currentDocument:wrap(10)
local guidedwrap = guided:wrap(10)
AssertEquals(2, #guidedwrap.lines)
AssertNotNull(guidedwrap.lines[1].trailingfragment)
AssertEquals(true, guidedwrap.lines[1].trailingfragment.hyphen)
AssertEquals("abc", guided[2]:sub(
	guidedwrap.lines[1].trailingfragment.start,
	guidedwrap.lines[1].trailingfragment.finish - 1))
AssertEquals("defgh", guided[2]:sub(
	guidedwrap.lines[2].leadingfragment.start, #guided[2]))

-- With no pattern recognising the word at all, wrapping still works exactly
-- as it did before this feature existed: the widest character cut that
-- satisfies the minimum.
withpatterns("UTF-8\nq1z\n")
local unguided = CreateParagraph("P", {"xx", "abcdefgh"})
currentDocument[1] = unguided
currentDocument:wrap(10)
local unguidedwrap = unguided:wrap(10)
AssertEquals(2, #unguidedwrap.lines)
AssertEquals("abcdef", unguided[2]:sub(
	unguidedwrap.lines[1].trailingfragment.start,
	unguidedwrap.lines[1].trailingfragment.finish - 1))

-- Several valid syllable boundaries exist ("ab", "cd" and "ef" gaps); the
-- widest one that both fits and meets the minimum is preferred, and it
-- moves to a narrower one as the available room shrinks -- exactly the
-- "widest that fits" preference the plain character-cut fallback already
-- has, now driven by real boundaries instead of arbitrary ones.
withpatterns("UTF-8\na1b\nc1d\ne1f\n")
local roomy = CreateParagraph("P", {"x", "abcdefgh"})
currentDocument[1] = roomy
currentDocument:wrap(10)
local roomywrap = roomy:wrap(10)
AssertNotNull(roomywrap.lines[1].trailingfragment)
AssertEquals("abcde", roomy[2]:sub(
	roomywrap.lines[1].trailingfragment.start,
	roomywrap.lines[1].trailingfragment.finish - 1))

local cramped = CreateParagraph("P", {"xxxx", "abcdefgh"})
currentDocument[1] = cramped
currentDocument:wrap(10)
local crampedwrap = cramped:wrap(10)
AssertNotNull(crampedwrap.lines[1].trailingfragment)
AssertEquals("abc", cramped[2]:sub(
	crampedwrap.lines[1].trailingfragment.start,
	crampedwrap.lines[1].trailingfragment.finish - 1))

-- Regression test for the reported bug: once a hyphenated word's remainder
-- opens a fresh line and fits there whole, it must be left alone -- not
-- hyphenated a second time just because a pattern also offers some other
-- syllable boundary further inside it (e.g. "docu-" / "men-" / "tos,"
-- instead of the correct "docu-" / "mentos,").
withpatterns("UTF-8\nc1d\nf1g\n")
local single = CreateParagraph("P", {"xxxxx", "abcdefgh"})
currentDocument[1] = single
currentDocument:wrap(10)
local singlewrap = single:wrap(10)
AssertEquals(2, #singlewrap.lines)
AssertNotNull(singlewrap.lines[1].trailingfragment)
AssertEquals("abc", single[2]:sub(
	singlewrap.lines[1].trailingfragment.start,
	singlewrap.lines[1].trailingfragment.finish - 1))
AssertEquals(nil, singlewrap.lines[2].fragment)
AssertEquals(nil, singlewrap.lines[2].trailingfragment)
AssertEquals("defgh", single[2]:sub(
	singlewrap.lines[2].leadingfragment.start, #single[2]))

GlobalSettings.hyphenation = {filenames = {}}
ResetHyphenationPatternCache()
