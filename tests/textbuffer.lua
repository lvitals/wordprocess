--!nonstrict
loadfile("tests/testsuite.lua")()

local dir = wg.mkdtemp()
local source = dir.."/source.txt"
local saved = dir.."/saved.txt"
local original = "alpha\nbeta\ngamma\n"
local _, e = wg.writefile(source, original)
AssertEquals(nil, e)

local buffer, openError = wg.opentextbuffer(source)
AssertEquals(nil, openError)
AssertEquals(#original, buffer:size())
AssertEquals("alpha", buffer:slice(0, 5))
AssertEquals(5, buffer:find(0, 10))
AssertEquals(16, buffer:rfind(0, 10, buffer:size()))

-- Saving an unchanged mapped source is a constant-time no-op. In particular,
-- it must not stream the complete source into an atomic temporary file.
AssertEquals(true, buffer:save(source))
AssertEquals(nil, wg.stat(source..".new"))
AssertEquals(original, wg.readfile(source))

buffer:insert(5, " edited")
AssertEquals("alpha edited\nbeta", buffer:slice(0, 17))
buffer:delete(5, 7)
AssertEquals(original, buffer:slice(0, buffer:size()))

buffer:insert(buffer:size(), "delta\n")
local ok, saveError = buffer:save(saved)
AssertEquals(true, ok)
AssertEquals(nil, saveError)
AssertEquals(original.."delta\n", wg.readfile(saved))
AssertEquals(original, wg.readfile(source))

-- Search must cross piece boundaries.
buffer:insert(2, "XYZ")
AssertEquals(1, buffer:findstring("lXYZp", 0))
AssertEquals(nil, buffer:findstring("not present", 0))
AssertEquals(true, buffer:undo())

-- Regression: Enter exactly at EOF creates a right-hand piece. Reverse line
-- lookup must inspect that piece instead of scanning the whole original mmap.
local eofDocument = assert(CreateTextBufferDocument(source))
currentDocument = eofDocument
AssertEquals(true, Cmd.GotoEndOfDocument())
local eof = eofDocument._textbuffer:size()
AssertEquals(true, Cmd.SplitCurrentParagraph())
AssertEquals(eof + 1, eofDocument._textpos)
local emptyLineStart = eofDocument:textLineBounds()
AssertEquals(eof + 1, emptyLineStart)
AssertEquals(true, Cmd.InsertStringIntoWord("x"))
local typedLineStart = eofDocument:textLineBounds()
AssertEquals(eof + 1, typedLineStart)
AssertEquals("\nx", eofDocument._textbuffer:slice(eof, 2))

local document, documentError = CreateTextBufferDocument(source)
AssertEquals(nil, documentError)
currentDocument = document
documentSet:addDocument(document, "mapped")

-- Every mapped save displays progress because index rebuilding and streaming
-- may take time even when the text itself is unchanged.
local oldImmediateMessage = ImmediateMessage
local savingMessage
ImmediateMessage = function(message) savingMessage = message end
document._textchanged = false
AssertEquals(true, ShowLargeTextSaveMessage(source))
AssertEquals("Saving...", savingMessage)
document._textchanged = true
AssertEquals(true, ShowLargeTextSaveMessage(source))
AssertEquals("Saving...", savingMessage)
ImmediateMessage = oldImmediateMessage

-- The non-undoable large-deletion warning is deferred until the command has
-- finished, so it remains the final visible message instead of being replaced
-- by the command's ordinary deletion confirmation.
local oldNonmodalMessage = NonmodalMessage
local deletionMessages = {}
NonmodalMessage = function(message)
	deletionMessages[#deletionMessages+1] = message
end
NonmodalMessage("Selected text deleted.")
FireAsyncEvent("LargeTextUndoHistoryCleared")
FlushAsyncEvents()
AssertEquals("Large deletion completed; undo history was cleared.",
	deletionMessages[#deletionMessages])
NonmodalMessage = oldNonmodalMessage

AssertEquals(true, document:moveTextLine(1))
AssertEquals(6, document._textpos)
AssertEquals(2, document._textline)
AssertEquals(true, Cmd.InsertStringIntoWord("mapped "))
AssertEquals("mapped beta", document._textbuffer:slice(6, 11))
AssertEquals(true, Cmd.DeleteSelectionOrPreviousChar())
AssertEquals("mappedbeta", document._textbuffer:slice(6, 10))
AssertEquals(true, Cmd.Undo())
AssertEquals("alpha\nmapped beta", document._textbuffer:slice(0, 17))
AssertEquals(true, Cmd.Undo())
AssertEquals("alpha\nbeta", document._textbuffer:slice(0, 10))
AssertEquals(true, Cmd.Redo())
AssertEquals("alpha\nmapped beta", document._textbuffer:slice(0, 17))
AssertEquals(true, Cmd.Redo())
AssertEquals("alpha\nmappedbeta", document._textbuffer:slice(0, 16))

-- The native backend keeps the normal status bar without exposing its
-- implementation name or pretending the one dummy paragraph is meaningful.
local status = {}
FireEvent("BuildStatusBar", status)
local statusText = {}
for _, term in ipairs(status) do statusText[#statusText+1] = term.value end
statusText = table.concat(statusText, " ")
AssertEquals(nil, statusText:lower():find("piece", 1, true))
AssertEquals(nil, statusText:find("P: 1/1", 1, true))
if not statusText:find("%", 1, true) then error("large-text status lacks percentage") end

-- UTF-8 movement/deletion operates on complete code points.
local utf8source = dir.."/utf8.txt"
local _, utf8error = wg.writefile(utf8source, "aç🙂z\nlast")
AssertEquals(nil, utf8error)
local utf8document = assert(CreateTextBufferDocument(utf8source))
currentDocument = utf8document

-- Viewport coordinates are terminal cells, while returned positions remain
-- byte offsets. Horizontal clipping must never split UTF-8 characters.
local visualsource = dir.."/visual.txt"
local _, visualerror = wg.writefile(visualsource, "ação日本語🙂é fim")
AssertEquals(nil, visualerror)
local visual = assert(CreateTextBufferDocument(visualsource))
local visualfinish = visual._textbuffer:size()
local displaystart, displayend, displaywidth =
	visual:textViewport(0, visualfinish, 5, 6)
AssertEquals("日", visual._textbuffer:slice(displaystart, 3))
if displaywidth > 6 then error("UTF-8 viewport exceeded terminal width") end
local display = visual._textbuffer:slice(displaystart, displayend-displaystart)
if not display:match("^[\228-\233]") then
	error("UTF-8 viewport started inside a continuation byte")
end

AssertEquals(true, Cmd.GotoNextCharW())
AssertEquals(1, utf8document._textpos)
AssertEquals(true, Cmd.GotoNextCharW())
AssertEquals(3, utf8document._textpos)
AssertEquals(true, Cmd.GotoNextCharW())
AssertEquals(7, utf8document._textpos)
AssertEquals(true, Cmd.DeleteSelectionOrPreviousChar())
AssertEquals("açz", utf8document._textbuffer:slice(0, 4))
AssertEquals(true, Cmd.Undo())
AssertEquals("aç🙂z", utf8document._textbuffer:slice(0, 8))

-- Byte-range selection, deletion, and undo stay inside the piece table.
utf8document._textpos = 1
Cmd.SetMark()
utf8document._textpos = 7
AssertEquals(true, Cmd.Delete())
AssertEquals("az\nlast", utf8document._textbuffer:slice(0,
	utf8document._textbuffer:size()))
AssertEquals(true, Cmd.Undo())
AssertEquals("aç🙂z\nlast", utf8document._textbuffer:slice(0,
	utf8document._textbuffer:size()))

utf8document._textpos = 0
AssertEquals(true, Cmd.GotoEndOfWord())
AssertEquals(8, utf8document._textpos)
AssertEquals(true, Cmd.GotoNextWord())
AssertEquals(9, utf8document._textpos)
AssertEquals(true, Cmd.GotoPreviousWord())
AssertEquals(0, utf8document._textpos)

local watchedsource = dir.."/watched.txt"
local _, watchedError = wg.writefile(watchedsource, "before")
AssertEquals(nil, watchedError)
local watched = assert(wg.opentextbuffer(watchedsource))
AssertEquals(false, watched:sourcechanged())
local _, changedError = wg.writefile(watchedsource, "after-change")
AssertEquals(nil, changedError)
AssertEquals(true, watched:sourcechanged())
watched:close()

-- Replacement of the pathname leaves the retained original mapping safe.
-- Save As may recover that editor view without overwriting the replacement.
local recoverSource = dir.."/recover-source.txt"
local replacement = dir.."/replacement.txt"
local recovered = dir.."/recovered.txt"
local _, recoverError = wg.writefile(recoverSource, "editor view\n")
AssertEquals(nil, recoverError)
local recoverDocument = assert(CreateTextBufferDocument(recoverSource))
local _, replacementError = wg.writefile(replacement, "external view\n")
AssertEquals(nil, replacementError)
assert(wg.rename(replacement, recoverSource))
AssertEquals(true, recoverDocument._textbuffer:sourcechanged())
AssertEquals(true, recoverDocument._textbuffer:sourcesafe())
currentDocument = recoverDocument
AssertEquals(true, Cmd.SaveCurrentDocumentAs(recovered))
AssertEquals("editor view\n", wg.readfile(recovered))
AssertEquals("external view\n", wg.readfile(recoverSource))
-- The successful Save As must have rebased every backing-store identity onto
-- recovered. Truncating the old A path must therefore be harmless and must not
-- affect source-change monitoring or subsequent mapped reads.
local _, truncateOldError = wg.writefile(recoverSource, "")
AssertEquals(nil, truncateOldError)
AssertEquals(false, recoverDocument._textbuffer:sourcechanged())
AssertEquals(true, recoverDocument._textbuffer:sourcesafe())
AssertEquals("editor view\n", recoverDocument._textbuffer:slice(0,
	recoverDocument._textbuffer:size()))

local edgeSource = dir.."/edges.txt"
local edgeData = "one\r\ntwo\n"..string.rep("x", 1024 * 1024).."\nlast"..
	string.char(0xff, 0xfe)
local _, edgeError = wg.writefile(edgeSource, edgeData)
AssertEquals(nil, edgeError)
local edgeDocument = assert(CreateTextBufferDocument(edgeSource))
local firstStart, firstFinish, firstNewline = edgeDocument:textLineBounds(0)
AssertEquals(0, firstStart)
AssertEquals(3, firstFinish)
AssertEquals(4, firstNewline)
edgeDocument._textpos = firstNewline + 1
local secondStart, secondFinish = edgeDocument:textLineBounds()
AssertEquals(5, secondStart)
AssertEquals(8, secondFinish)
AssertEquals(true, edgeDocument:moveTextLine(1))
local longStart, longFinish = edgeDocument:textLineBounds()
AssertEquals(9, longStart)
AssertEquals(9 + 1024 * 1024, longFinish)
edgeDocument._textpos = edgeDocument._textbuffer:size()
local lastStart, lastFinish = edgeDocument:textLineBounds()
AssertEquals(longFinish + 1, lastStart)
AssertEquals(edgeDocument._textbuffer:size(), lastFinish)

-- Exercise piece splits and cross-piece deletions against a plain Lua string.
local model = original.."delta\n"
for i = 1, 100 do
	local position = (i * 17) % (#model + 1)
	local addition = "<"..i..">"
	buffer:insert(position, addition)
	model = model:sub(1, position)..addition..model:sub(position + 1)
	local available = #model - position
	local deletion = math.min(i % 5, available)
	buffer:delete(position, deletion)
	model = model:sub(1, position)..model:sub(position + deletion + 1)
	AssertEquals(model, buffer:slice(0, buffer:size()))
end

-- Native large .wp files keep metadata separate from a mapped content region.
-- Saving and loading must not turn the file into disguised plain text.
local nativeSource = dir.."/native-source.txt"
local nativePath = dir.."/large-native.wp"
local nativeText = "first line\nsecond line\n"
AssertEquals(nil, select(2, wg.writefile(nativeSource, nativeText)))
local nativeDocument = assert(CreateTextBufferDocument(nativeSource))
documentSet = CreateDocumentSet()
documentSet.menu = CreateMenuTree()
documentSet:addDocument(nativeDocument, "Large document")
documentSet:setCurrent("Large document")
currentDocument = nativeDocument
currentDocument._textmark = 0
currentDocument._textpos = 5
currentDocument.mp = 1
AssertEquals(true, Cmd.SetStyle("b"))
currentDocument._textpos = 0
AssertEquals(true, Cmd.ChangeParagraphStyle("H1"))
AssertEquals(true, Cmd.SaveCurrentDocumentAs(nativePath))
local nativeBytes = assert(wg.readfile(nativePath))
AssertEquals("WordProcess document v1", nativeBytes:match("^[^\n]+"))
AssertEquals(true, #nativeBytes > #nativeText)
AssertEquals(nil, nativeBytes:find(".largeDocument", 1, true))
AssertEquals(true, nativeBytes:find(".documentIndex", 1, true) ~= nil)

local futurePath = dir.."/future-native.wp"
AssertEquals(nil, select(2, wg.writefile(futurePath,
	nativeBytes:gsub("^WordProcess document v1", "WordProcess document v2"))))
local futureDocument, futureError = LoadFromFile(futurePath)
AssertEquals(nil, futureDocument)
AssertEquals(true, futureError:find("requires a newer application", 1, true) ~= nil)

local loadedNative, nativeLoadError = LoadFromFile(nativePath)
AssertEquals(nil, nativeLoadError)
AssertNotNull(loadedNative)
AssertEquals(true, loadedNative.current:usesTextBuffer())
AssertEquals(true, loadedNative.current._nativeLarge)
AssertEquals(nil, loadedNative.current.largeDocument)
AssertEquals(3, loadedNative.current.documentIndex.lineCount)
AssertEquals(4096, loadedNative.current.documentIndex.lineIndexStride)
AssertEquals(0, loadedNative.current.documentIndex.lineOffsets[1])
AssertEquals(4, loadedNative.current.documentIndex.wordCount)
AssertNotNull(loadedNative.current.documentIndex.paragraphStyles)
AssertNotNull(loadedNative.current.documentIndex.characterStyles)
AssertEquals(true, bit32.btest(loadedNative.current:largeCharacterStyleAt(0), wg.BOLD))
AssertEquals("H1", loadedNative.current:largeParagraphStyleAt(0))
loadedNative.current:addLargeCharacterStyle(0, 5, wg.ITALIC)
AssertEquals(true, bit32.btest(
	loadedNative.current:largeCharacterStyleAt(2), wg.BOLD))
AssertEquals(true, bit32.btest(
	loadedNative.current:largeCharacterStyleAt(2), wg.ITALIC))
loadedNative.current:addLargeCharacterStyle(0, 5, 0)
AssertEquals(0, loadedNative.current:largeCharacterStyleAt(2))
loadedNative.current:addLargeCharacterStyle(0, 5, wg.BOLD)
AssertEquals(nativeText, loadedNative.current._textbuffer:slice(0,
	loadedNative.current._textbuffer:size()))

documentSet = loadedNative
currentDocument = loadedNative.current
currentDocument._textbuffer:insert(0, "edited ")
currentDocument:adjustLargeStyleSpans(0, 0, #"edited ")
currentDocument._textchanged = true
AssertEquals(true, bit32.btest(currentDocument:largeCharacterStyleAt(0), wg.BOLD))
AssertEquals("H1", currentDocument:largeParagraphStyleAt(0))
AssertEquals(true, Cmd.SaveCurrentDocument())
local reloadedNative = assert(LoadFromFile(nativePath))
AssertEquals("edited "..nativeText, reloadedNative.current._textbuffer:slice(0,
	reloadedNative.current._textbuffer:size()))

-- Ctrl-G has the same table-of-contents meaning for mapped and ordinary
-- documents. It reads only sparse heading spans and bounded title slices.
documentSet = reloadedNative
currentDocument = reloadedNative.current
local loadedPageIndex = currentDocument:ensureDocumentIndex().pageLayoutIndex
AssertNotNull(loadedPageIndex)
documentSet:touch(true)
AssertEquals(loadedPageIndex,
	currentDocument:ensureDocumentIndex().pageLayoutIndex)
documentSet:clean()
currentDocument:addLargeParagraphStyle(18, 29, "H2")
currentDocument._textpos = currentDocument._textbuffer:size()
local oldFormRun = Form.Run
Form.Run = function(dialogue)
	AssertEquals("Go To", dialogue.title)
	AssertEquals(2, #dialogue.widgets[2].data)
	AssertEquals("1. edited first line", dialogue.widgets[2].data[1].label)
	AssertEquals("   1.1. second line", dialogue.widgets[2].data[2].label)
	AssertEquals(2, dialogue.widgets[2].cursor)
	dialogue.widgets[2].cursor = 1
	return true
end
AssertEquals(true, Cmd.Goto())
AssertEquals(0, currentDocument._textpos)
Form.Run = oldFormRun

-- Structural and positional navigation share the saved sparse index. Each
-- line lookup scans forward from at most one 4096-line checkpoint.
AssertEquals(3, currentDocument:getLineCount())
AssertEquals(1, currentDocument:getLineAtPosition(0))
AssertEquals(2, currentDocument:getLineAtPosition(18))
AssertEquals(18, currentDocument:getPositionForLine(2))
AssertEquals(nil, currentDocument:getPositionForLine(0))
AssertEquals(nil, currentDocument:getPositionForLine(4))
AssertEquals(0, currentDocument:getPositionForPercent(0))
AssertEquals(currentDocument._textbuffer:size(),
	currentDocument:getPositionForPercent(100))
local middlePosition = assert(currentDocument:getPositionForPercent(50))
local middleByte = currentDocument._textbuffer:slice(middlePosition, 1):byte()
AssertEquals(true, not middleByte or middleByte < 0x80 or middleByte >= 0xc0)
-- Native mapped documents use their own sparse physical-layout checkpoints,
-- never the word, line, percentage, or paragraph totals.
AssertEquals(1, currentDocument:getPageCount())
AssertEquals(1, currentDocument:getPageAtPosition(0))
AssertEquals(0, currentDocument:getPositionForPage(1))
AssertEquals(nil, currentDocument:getPositionForPage(0))
local navigationStatus = {}
FireEvent("BuildStatusBar", navigationStatus)
local navigationText = {}
for _, term in ipairs(navigationStatus) do navigationText[#navigationText+1] = term.value end
navigationText = table.concat(navigationText, " | ")
AssertEquals(true, navigationText:find("Pg: 1/1", 1, true) ~= nil)
local _, percentages = navigationText:gsub("%%", "")
AssertEquals(1, percentages)

local function runPositionalGoto(focus, value)
	Form.Run = function(dialogue)
		dialogue.focus = focus
		dialogue.widgets[focus].value = value
		return true
	end
	AssertEquals(true, Cmd.Goto())
	Form.Run = oldFormRun
end
runPositionalGoto(6, "3")
AssertEquals(3, currentDocument._textline)
AssertEquals(currentDocument:getPositionForLine(3), currentDocument._textpos)
runPositionalGoto(8, "100")
AssertEquals(currentDocument._textbuffer:size(), currentDocument._textpos)
runPositionalGoto(4, "1")
AssertEquals(0, currentDocument._textpos)

-- Corrupt metadata is rejected before it can construct indexed objects.
local corruptPath = dir.."/corrupt-native.wp"
local savedNative = assert(wg.readfile(nativePath))
local _, metadataStart = assert(savedNative:find("\n\n", 1, true))
metadataStart = metadataStart + 1
local damaged = savedNative:sub(1, metadataStart - 1)..
	string.char(bit32.bxor(savedNative:byte(metadataStart), 1))..
	savedNative:sub(metadataStart + 1)
AssertEquals(nil, select(2, wg.writefile(corruptPath, damaged)))
local corruptDocument, corruptError = LoadFromFile(corruptPath)
AssertEquals(nil, corruptDocument)
AssertEquals(true, corruptError:find("metadata checksum failed", 1, true) ~= nil)

-- A sparse file above 4 GiB validates 64-bit offsets without allocating or
-- writing four physical GiB. Opening and editing remain bounded.
local sparsePath = dir.."/sparse-4g.txt"
AssertEquals(nil, select(2, wg.writefile(sparsePath, "")))
local sparseSize = 4 * 1024 * 1024 * 1024 + 4096
AssertEquals(true, wg.truncatefile(sparsePath, sparseSize))
local sparseDocument = assert(CreateTextBufferDocument(sparsePath))
AssertEquals(sparseSize, sparseDocument._textbuffer:size())
AssertEquals("\0", sparseDocument._textbuffer:slice(sparseSize - 1, 1))
AssertEquals(math.floor(sparseSize / 2),
	sparseDocument:getPositionForPercent(50))
AssertEquals(sparseSize, sparseDocument:getPositionForPercent(100))
documentSet = CreateDocumentSet()
documentSet.menu = CreateMenuTree()
documentSet:addDocument(sparseDocument, "Sparse journal")
currentDocument = sparseDocument
local unknownPageStatus = {}
FireEvent("BuildStatusBar", unknownPageStatus)
local unknownPageText = {}
for _, term in ipairs(unknownPageStatus) do unknownPageText[#unknownPageText+1] = term.value end
AssertEquals(true, table.concat(unknownPageText, " | "):
	find("Pg: ?/?", 1, true) ~= nil)
sparseDocument._textbuffer:insert(sparseSize - 1, "x")
AssertEquals("x\0", sparseDocument._textbuffer:slice(sparseSize - 1, 2))
sparseDocument:adjustLargeStyleSpans(sparseSize - 1, 0, 1)
sparseDocument:addLargeCharacterStyle(sparseSize - 1, sparseSize, wg.BOLD)
local sparseJournal = dir.."/sparse-4g.autosave.wp"
AssertEquals(true, sparseDocument._textbuffer:journal(sparseJournal,
	SaveToHeaderlessString(documentSet)))
AssertEquals(true, assert(wg.stat(sparseJournal)).size < 1024*1024)
local recoveredSparse, recoveredError = LoadFromFile(sparseJournal)
AssertEquals(nil, recoveredError)
AssertNotNull(recoveredSparse)
AssertEquals(sparseSize + 1, recoveredSparse.current._textbuffer:size())
AssertEquals("x\0", recoveredSparse.current._textbuffer:slice(sparseSize - 1, 2))
AssertEquals(true, bit32.btest(recoveredSparse.current:
	largeCharacterStyleAt(sparseSize - 1), wg.BOLD))
recoveredSparse.current._textbuffer:close()
sparseDocument._textbuffer:close()

-- Structured mapped clipboard payloads restore character and paragraph spans.
local clipPath = dir.."/mapped-clipboard.txt"
AssertEquals(nil, select(2, wg.writefile(clipPath, "hello world")))
local clipDocument = assert(CreateTextBufferDocument(clipPath))
documentSet = CreateDocumentSet()
documentSet.menu = CreateMenuTree()
documentSet:addDocument(clipDocument, "clipboard source")
currentDocument = clipDocument
clipDocument:addLargeCharacterStyle(0, 5, wg.BOLD)
clipDocument:addLargeParagraphStyle(0, 5, "H1")
clipDocument._textmark, clipDocument._textpos, clipDocument.mp = 0, 5, 1
AssertEquals(true, Cmd.Copy())
clipDocument._textpos = clipDocument._textbuffer:size()
AssertEquals(true, Cmd.Paste())
AssertEquals("hello worldhello", clipDocument._textbuffer:slice(0,
	clipDocument._textbuffer:size()))
AssertEquals(true, bit32.btest(clipDocument:largeCharacterStyleAt(12), wg.BOLD))
AssertEquals("H1", clipDocument:largeParagraphStyleAt(12))

-- Smart quotes edit bounded mapped selections and preserve adjacent styles.
documentSet.addons.smartquotes = {
	doublequotes=true, singlequotes=true, notinraw=true,
	leftdouble="“", rightdouble="”", leftsingle="‘", rightsingle="’"
}
clipDocument._textbuffer:insert(0, '"quoted" ')
clipDocument:adjustLargeStyleSpans(0, 0, 9)
clipDocument._textmark, clipDocument._textpos = 0, 8
AssertEquals(true, Cmd.Smartquotify())
AssertEquals("“quoted”", clipDocument._textbuffer:slice(0, 12))
AssertEquals(true, Cmd.Unsmartquotify())
AssertEquals('"quoted"', clipDocument._textbuffer:slice(0, 8))

-- Offline spellchecking scans mapped content in bounded windows and wraps.
documentSet.addons.spellchecker = {
	enabled=true, usesystemdictionary=true, useuserdictionary=false
}
SetSystemDictionaryForTesting({"quoted", "hello", "world"})
clipDocument._textmark = nil
clipDocument._textpos = 0
AssertEquals(true, Cmd.FindNextMisspeltWord())
AssertEquals("worldhello", GetWordSimpleText(clipDocument._textbuffer:slice(
	clipDocument._textmark, clipDocument._textpos-clipDocument._textmark)))

-- Every structured exporter consumes mapped paragraphs without assembling the
-- complete output in a Lua table. ODT streams content.xml from a temporary file.
clipDocument._textmark = nil
documentSet.addons.htmlexport = {
	italic_on="<i>", italic_off="</i>", underline_on="<u>",
	underline_off="</u>", bold_on="<b>", bold_off="</b>"
}
local exports = {
	{Cmd.ExportMarkdownFile, "/mapped.md"},
	{Cmd.ExportHTMLFile, "/mapped.html"},
	{Cmd.ExportLatexFile, "/mapped.tex"},
	{Cmd.ExportOrgFile, "/mapped.org"},
	{Cmd.ExportTroffFile, "/mapped.tr"},
}
for _, export in ipairs(exports) do
	local path = dir..export[2]
	AssertEquals(true, export[1](path))
	AssertEquals(true, #assert(wg.readfile(path)) > 0)
end
local odtPath = dir.."/mapped.odt"
AssertEquals(true, Cmd.ExportODTFile(odtPath))
AssertEquals(true, assert(wg.readfromzip(odtPath, "content.xml")):
	find("quoted", 1, true) ~= nil)

-- Fault injection is one-shot and leaves an existing destination untouched at
-- each pre-commit save phase.
local faultSource = dir.."/fault-source.txt"
local faultTarget = dir.."/fault-target.txt"
AssertEquals(nil, select(2, wg.writefile(faultSource, "source")))
AssertEquals(nil, select(2, wg.writefile(faultTarget, "original")))
local faultBuffer = assert(wg.opentextbuffer(faultSource))
faultBuffer:insert(faultBuffer:size(), " changed")
for _, phase in ipairs({"temporary", "write", "sync", "rename"}) do
	wg.setsavefault(phase)
	AssertEquals(nil, faultBuffer:save(faultTarget))
	AssertEquals("original", wg.readfile(faultTarget))
end
AssertEquals(true, faultBuffer:save(faultTarget))
AssertEquals("source changed", wg.readfile(faultTarget))
