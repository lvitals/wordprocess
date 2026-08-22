--!nonstrict
loadfile("tests/testsuite.lua")()

-- Meson's dictionary_path remains the default across upgrades, while a path
-- explicitly selected in the editor remains authoritative.
GlobalSettings.systemdictionary = {filename="obsolete-default", custom=false}
FireEvent("RegisterAddons")
AssertEquals(DEFAULT_DICTIONARY_PATH, GlobalSettings.systemdictionary.filename)
GlobalSettings.systemdictionary = {filename="explicit-selection", custom=true}
FireEvent("RegisterAddons")
AssertEquals("explicit-selection", GlobalSettings.systemdictionary.filename)
GlobalSettings.systemdictionary = {filename="legacy-saved-selection"}
FireEvent("RegisterAddons")
AssertEquals("legacy-saved-selection", GlobalSettings.systemdictionary.filename)
AssertEquals(true, GlobalSettings.systemdictionary.custom)
GlobalSettings.systemdictionary.filename = nil

-- Sorted dictionaries are searched directly through the mapped large-file
-- backend. Exercise first/middle/last lines, misses on either side and an EOF
-- without a trailing newline.
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
AssertTableEquals({"fnord"}, unset(GetUserDictionary()))

Cmd.DeleteWord()
Cmd.AddToUserDictionary()
AssertTableEquals({"fnord"}, unset(GetUserDictionary()))

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
AssertEquals(true, IsWordMisspelt("Lower", false))

AssertEquals(true, IsWordMisspelt("LOWER", true))
AssertEquals(true, IsWordMisspelt("LOWER", false))

AssertEquals(true, IsWordMisspelt("upper", true))
AssertEquals(true, IsWordMisspelt("Upper", true))
AssertEquals(true, IsWordMisspelt("upper", false))
AssertEquals(true, IsWordMisspelt("Upper", false))

AssertEquals(false, IsWordMisspelt("UPPER", true))
AssertEquals(false, IsWordMisspelt("UPPER", false))

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
