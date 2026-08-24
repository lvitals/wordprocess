--!nonstrict
loadfile("tests/testsuite.lua")()

-- Dictionary discovery is directory based and includes newly installed
-- language files automatically; the filesystem layer marks symlink aliases.
local discoveryDir = wg.mkdtemp()
AssertEquals(nil, select(2, wg.writefile(discoveryDir.."/american-english", "hello\n")))
AssertEquals(nil, select(2, wg.writefile(discoveryDir.."/portuguese-brazilian", "olá\n")))
AssertEquals(nil, select(2, wg.writefile(discoveryDir.."/words", "ambiguous\n")))
AssertTableEquals({
	discoveryDir.."/american-english",
	discoveryDir.."/portuguese-brazilian",
	discoveryDir.."/words",
}, DiscoverSystemDictionaries(discoveryDir))

-- Meson's dictionary_path remains the default across upgrades, while a path
-- explicitly selected in the editor remains authoritative.
GlobalSettings.systemdictionary = {filename="obsolete-default", custom=false}
FireEvent("RegisterAddons")
AssertEquals(DEFAULT_DICTIONARY_PATH, GlobalSettings.systemdictionary.filename)
AssertTableEquals(DEFAULT_DICTIONARY_PATH == "" and {} or
	{DEFAULT_DICTIONARY_PATH}, GlobalSettings.systemdictionary.filenames)
GlobalSettings.systemdictionary = {filename="explicit-selection", custom=true}
FireEvent("RegisterAddons")
AssertEquals("explicit-selection", GlobalSettings.systemdictionary.filename)
AssertTableEquals(DEFAULT_DICTIONARY_PATH == "" and {"explicit-selection"} or
	{DEFAULT_DICTIONARY_PATH, "explicit-selection"},
	GlobalSettings.systemdictionary.filenames)
GlobalSettings.systemdictionary = {filename="legacy-saved-selection"}
FireEvent("RegisterAddons")
AssertEquals("legacy-saved-selection", GlobalSettings.systemdictionary.filename)
AssertEquals(true, GlobalSettings.systemdictionary.custom)
GlobalSettings.systemdictionary.filename = nil

-- Dictionaries are required to be sorted (see docs/hunspell-wordlists.md),
-- which lets lookups binary-search the mapped large-file backend instead of
-- loading or indexing the entire file. Exercise present words, misses and an
-- EOF without a trailing newline.
local mappedDictionaryPath = wg.mkdtemp().."/sorted.words"
AssertEquals(nil, select(2, wg.writefile(mappedDictionaryPath,
	"alpha\nmundo\nomega")))
GlobalSettings.systemdictionary = {filename=mappedDictionaryPath, custom=true}
GlobalSettings.spellchecker.enabled = true
GlobalSettings.spellchecker.usesystemdictionary = true
GlobalSettings.spellchecker.useuserdictionary = false
ResetSystemDictionaryCache()
AssertEquals(false, IsWordMisspelt("alpha", false))
AssertEquals(false, IsWordMisspelt("mundo", false))
AssertEquals(false, IsWordMisspelt("omega", false))
AssertEquals(true, IsWordMisspelt("aardvark", false))
AssertEquals(true, IsWordMisspelt("beta", false))
AssertEquals(true, IsWordMisspelt("zeta", false))
AssertEquals("mapped", GetSystemDictionary().kind)
ResetSystemDictionaryCache()

-- A word far from the start of a large dictionary remains available without
-- loading or indexing the complete word list, and lookups stay fast
-- regardless of dictionary size: this line count would take a very long time
-- to index up front, so the test itself times out if that ever regresses.
local largeDictionaryPath = wg.mkdtemp().."/large.words"
local paddingLines = 200000
local paddingContent = {}
for i = 1, paddingLines do
	paddingContent[i] = string.format("filler%06d", i)
end
AssertEquals(nil, select(2, wg.writefile(largeDictionaryPath,
	table.concat(paddingContent, "\n").."\nneedle\n")))
GlobalSettings.systemdictionary = {
	filenames={largeDictionaryPath}, custom=true,
}
ResetSystemDictionaryCache()
local searchStart = os.clock()
AssertEquals(false, IsWordMisspelt("needle", false))
AssertEquals(false, IsWordMisspelt("filler000001", false))
AssertEquals(false, IsWordMisspelt("filler199999", false))
AssertEquals(true, IsWordMisspelt("missingword", false))
local searchDuration = os.clock() - searchStart
AssertEquals(true, searchDuration < 2.0)
ResetSystemDictionaryCache()

-- More than one selected word list is searched. A word is accepted when it
-- occurs in any dictionary, which allows English and Portuguese lists to be
-- enabled together.
local englishDictionaryPath = wg.mkdtemp().."/english.words"
local portugueseDictionaryPath = wg.mkdtemp().."/pt_BR.words"
AssertEquals(nil, select(2, wg.writefile(englishDictionaryPath,
	"hello\nworld\n")))
AssertEquals(nil, select(2, wg.writefile(portugueseDictionaryPath,
	"mundo\nolá\n")))
GlobalSettings.systemdictionary = {
	filenames={englishDictionaryPath, portugueseDictionaryPath}, custom=true,
}
ResetSystemDictionaryCache()
AssertEquals(false, IsWordMisspelt("hello", false))
AssertEquals(false, IsWordMisspelt("mundo", false))
AssertEquals(true, IsWordMisspelt("missing", false))
AssertEquals("multiple", GetSystemDictionary().kind)
AssertEquals(2, #GetSystemDictionary().dictionaries)
ResetSystemDictionaryCache()

local function unset(s)
	local a = {}
	for k in pairs(s) do
		a[#a+1] = k
	end
	return a
end

SetSystemDictionaryForTesting({"lower", "UPPER", "there's"})

-- A visual hyphen at the end of a wrapped line is not part of the stored
-- word and must not create a false spelling error.
SetSystemDictionaryForTesting({"completeword"})
GlobalSettings.spellchecker.enabled = true
GlobalSettings.spellchecker.usesystemdictionary = true
GlobalSettings.spellchecker.useuserdictionary = false
local wrappedPayload = {
	word="complete-", spellingWord="completeword",
	firstword=false, cstyle=0, ostyle=0,
}
FireEvent("DrawWord", wrappedPayload)
AssertEquals(0, wrappedPayload.cstyle)
local literalHyphenPayload = {
	word="complete-", firstword=false, cstyle=0, ostyle=0,
}
FireEvent("DrawWord", literalHyphenPayload)
AssertEquals(wg.UNDERLINE, literalHyphenPayload.cstyle)
AssertEquals(Palette.MisspeltFG, literalHyphenPayload.fg)
SetSystemDictionaryForTesting({"lower", "UPPER", "there's"})

Cmd.InsertStringIntoWord("fnord")
Cmd.AddToUserDictionary()
AssertEquals("fnord", GetUserDictionary().fnord)

Cmd.DeleteWord()
Cmd.AddToUserDictionary()
AssertEquals("fnord", GetUserDictionary().fnord)

GlobalSettings.spellchecker.enabled = false
local payload = { word="fnord", cstyle=0, ostyle=0 }
FireEvent("DrawWord", payload)
AssertTableEquals({"fnord", 0, 0},
	{payload.word, payload.cstyle, payload.ostyle})

GlobalSettings.spellchecker.enabled = true
GlobalSettings.spellchecker.useuserdictionary = true
GlobalSettings.spellchecker.usesystemdictionary = false
local payload = { word="fnord", cstyle=0, ostyle=0 }
FireEvent("DrawWord", payload)
AssertTableEquals({"fnord", 0, 0},
	{payload.word, payload.cstyle, payload.ostyle})

local payload = { word="fnord.", cstyle=0, ostyle=0 }
FireEvent("DrawWord", payload)
AssertTableEquals({"fnord.", 0, 0},
	{payload.word, payload.cstyle, payload.ostyle})

local payload = { word="There’s", cstyle=0, ostyle=0 }
FireEvent("DrawWord", payload)
AssertTableEquals({"There’s", wg.UNDERLINE, 0},
	{payload.word, payload.cstyle, payload.ostyle})

local payload = { word="notfound", cstyle=0, ostyle=0 }
FireEvent("DrawWord", payload)
AssertTableEquals({"notfound", wg.UNDERLINE, 0},
	{payload.word, payload.cstyle, payload.ostyle})

GlobalSettings.spellchecker.enabled = true
GlobalSettings.spellchecker.useuserdictionary = true
GlobalSettings.spellchecker.usesystemdictionary = true
AssertEquals(false, IsWordMisspelt("lower", true))
AssertEquals(false, IsWordMisspelt("Lower", true))
AssertEquals(false, IsWordMisspelt("lower", false))
AssertEquals(false, IsWordMisspelt("Lower", false))

-- Unknown title-case words inside a sentence are treated as proper names,
-- while the same token at a sentence boundary is still checked normally.
AssertEquals(false, IsWordMisspelt("Maristela", false))
AssertEquals(false, IsWordMisspelt("Maristela", true))

AssertEquals(false, IsWordMisspelt("LOWER", true))
AssertEquals(false, IsWordMisspelt("LOWER", false))

AssertEquals(true, IsWordMisspelt("upper", true))
AssertEquals(false, IsWordMisspelt("Upper", true))
AssertEquals(true, IsWordMisspelt("upper", false))
AssertEquals(false, IsWordMisspelt("Upper", false))

AssertEquals(false, IsWordMisspelt("UPPER", true))
AssertEquals(false, IsWordMisspelt("UPPER", false))

-- Technical tokens used by compatibility-09.wp are identifiers or keyboard
-- combinations, not prose words. No individual key name is hard-coded.
SetSystemDictionaryForTesting({"WordPress", "favourite", "customisation",
	"navigation", "italicised", "style", "italic", "plain", "underline",
	"word", "process", "sub", "documents", "letter", "glyph", "path",
	"name", "chip", "set"})
AssertEquals(false, IsWordMisspelt("WordPress", false))
AssertEquals(false, IsWordMisspelt("WordProcess", true))
AssertEquals(false, IsWordMisspelt("favourite", false))
AssertEquals(false, IsWordMisspelt("customisation", false))
AssertEquals(false, IsWordMisspelt("Navigation", true))
AssertEquals(false, IsWordMisspelt("Italicised", true))
AssertEquals(false, IsWordMisspelt("Style→Italic", false))
AssertEquals(false, IsWordMisspelt("Style→Plain", false))
AssertEquals(false, IsWordMisspelt("Style→Underline", false))
AssertEquals(false, IsWordMisspelt("subdocuments", false))
AssertEquals(false, IsWordMisspelt("glyphs", false))
AssertEquals(false, IsWordMisspelt("pathname", false))
AssertEquals(false, IsWordMisspelt("chipset", false))
AssertEquals(false, IsWordMisspelt("ESC", false))
AssertEquals(false, IsWordMisspelt("RETURN", false))
AssertEquals(false, IsWordMisspelt("CTRL+C", false))
AssertEquals(false, IsWordMisspelt("ALT+letter", false))
AssertEquals(false, IsWordMisspelt("<li>", false))
AssertEquals(false, IsWordMisspelt("cmd.exe", false))
AssertEquals(false, IsWordMisspelt("--exec", false))
AssertEquals(false, IsWordMisspelt('ListMenuItems()', false))
AssertEquals(false, IsWordMisspelt('c:\\fonts\\myfont.ttf', false))
SetSystemDictionaryForTesting({"lower", "UPPER", "there's"})

AssertEquals(false, IsWordMisspelt("there’s", false))
AssertEquals(true, IsWordMisspelt("There’s", false))
AssertEquals(false, IsWordMisspelt("there’s", true))
AssertEquals(false, IsWordMisspelt("There’s", true))

GlobalSettings.spellchecker.useuserdictionary = true
GlobalSettings.spellchecker.usesystemdictionary = true
local payload = { word="fnord", cstyle=0, ostyle=0 }
FireEvent("DrawWord", payload)
AssertTableEquals({"fnord", 0, 0},
	{payload.word, payload.cstyle, payload.ostyle})

-- FindNextMisspeltWord

SetSystemDictionaryForTesting({"bar", "exclamation", "correct"})

Cmd.InsertStringIntoParagraph("foo bar baz exclamation! Correct. incorroct")
Cmd.GotoBeginningOfDocument()
Cmd.FindNextMisspeltWord()
AssertTableEquals({1, 1, 1}, {currentDocument.mp, currentDocument.mw, currentDocument.mo})
AssertTableEquals({1, 1, 4}, {currentDocument.cp, currentDocument.cw, currentDocument.co})

Cmd.FindNextMisspeltWord()
AssertTableEquals({1, 3, 1}, {currentDocument.mp, currentDocument.mw, currentDocument.mo})
AssertTableEquals({1, 3, 4}, {currentDocument.cp, currentDocument.cw, currentDocument.co})

Cmd.FindNextMisspeltWord()
AssertTableEquals({1, 6, 1}, {currentDocument.mp, currentDocument.mw, currentDocument.mo})
AssertTableEquals({1, 6, 10}, {currentDocument.cp, currentDocument.cw, currentDocument.co})
