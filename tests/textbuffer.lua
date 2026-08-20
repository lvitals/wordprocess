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

local document, documentError = CreateTextBufferDocument(source)
AssertEquals(nil, documentError)
currentDocument = document
documentSet:addDocument(document, "mapped")

-- Slow large-file writes display the centred notice, while an unchanged save
-- to the mapped source remains silent because it is constant-time.
local oldImmediateMessage = ImmediateMessage
local savingMessage
ImmediateMessage = function(message) savingMessage = message end
document._textchanged = false
AssertEquals(false, ShowLargeTextSaveMessage(source))
AssertEquals(nil, savingMessage)
document._textchanged = true
AssertEquals(true, ShowLargeTextSaveMessage(source))
AssertEquals("Saving...", savingMessage)
ImmediateMessage = oldImmediateMessage

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
