--!nonstrict
loadfile("tests/testsuite.lua")()

-- Regression test: everything a document holds -- not just its plain text
-- -- must survive a save/destroy/reload cycle intact. This is a different
-- guarantee from the load-compatibility-*.lua tests, which prove that old
-- file *formats* still load; this proves round-trip *fidelity* of the
-- current format: what was saved is what comes back.

local function dumpparagraphs()
	local paragraphs = {}
	for i, p in ipairs(currentDocument) do
		paragraphs[i] = {style = p.style, words = {table.unpack(p)}}
	end
	return paragraphs
end

local function dumplayout()
	local layout = {}
	for k, v in pairs(currentDocument.pageLayout) do
		layout[k] = v
	end
	return layout
end

-- Plain paragraph.
Cmd.InsertStringIntoParagraph("plain paragraph")
Cmd.GotoEndOfParagraph()
Cmd.SplitCurrentParagraph()

-- Character style (bold) mid-word.
Cmd.InsertStringIntoParagraph("foobar")
Cmd.SetMark()
Cmd.GotoPreviousCharW()
Cmd.GotoPreviousCharW()
Cmd.GotoPreviousCharW()
Cmd.SetStyle("b")
Cmd.GotoEndOfParagraph()
Cmd.SplitCurrentParagraph()

-- A tab.
Cmd.InsertStringIntoParagraph("a")
Cmd.InsertTab()
local tabmarkerword = currentDocument.cw - 1
Cmd.InsertStringIntoParagraph("b")
Cmd.GotoEndOfParagraph()
Cmd.SplitCurrentParagraph()

-- A different paragraph style.
Cmd.InsertStringIntoParagraph("A Heading")
Cmd.ChangeParagraphStyle("H1")

AssertEquals(4, #currentDocument)
if not WordHasTabMarker(currentDocument[3][tabmarkerword]) then
	error("test setup: expected a tab marker in paragraph 3")
end

-- A non-default page layout.
ApplyPageLayoutProfile(currentDocument, "ABNT")
currentDocument.pageLayout.pageWidthCm = 18.5 -- deliberately not any preset's value

-- The current document's own name (distinguishing it within the set) is
-- content. documentSet.name is not checked here -- it's the path last
-- loaded from/saved to, and loading deliberately overwrites it to the
-- filename being loaded (src/lua/fileio.lua's loaddocument()), regardless
-- of what was serialized.
currentDocument.name = "roundtrip-doc"

local before = {
	documentname = currentDocument.name,
	tabmarker = WordHasTabMarker(currentDocument[3][tabmarkerword]),
	paragraphs = dumpparagraphs(),
	layout = dumplayout(),
}

local filename = wg.mkdtemp() .. "/roundtrip.wp"
local ok, err = SaveDocumentSetRaw(filename)
if not ok then
	error("failed to save: " .. tostring(err))
end

-- Destroy: not "close one document" but the whole in-memory session torn
-- down and replaced, the same as restarting the application.
ResetDocumentSet()
AssertEquals(1, #currentDocument)
AssertEquals("", currentDocument[1]:asString())

-- A global editor preference must not travel with the .wp file, and must
-- not be clobbered by loading one -- see
-- margin-mode-follows-default-on-create.lua for the regression this
-- generalises from.
GlobalSettings.lookandfeel.tabwidth = 9

AssertEquals(true, Cmd.LoadDocumentSet(filename))

local after = {
	documentname = currentDocument.name,
	tabmarker = WordHasTabMarker(currentDocument[3][tabmarkerword]),
	paragraphs = dumpparagraphs(),
	layout = dumplayout(),
}

AssertEquals(before.documentname, after.documentname)
AssertEquals(before.tabmarker, after.tabmarker)

AssertEquals(#before.paragraphs, #after.paragraphs)
for i = 1, #before.paragraphs do
	AssertEquals(before.paragraphs[i].style, after.paragraphs[i].style)
	AssertTableEquals(before.paragraphs[i].words, after.paragraphs[i].words)
end

for k, v in pairs(before.layout) do
	AssertEquals(v, after.layout[k])
end

-- The document content round-tripped; the global preference set *between*
-- save and load must be untouched by the load.
AssertEquals(9, GlobalSettings.lookandfeel.tabwidth)
