--!nonstrict
-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local ITALIC = wg.ITALIC
local UNDERLINE = wg.UNDERLINE
local BOLD = wg.BOLD
local ParseWord = wg.parseword
local bitand = bit32.band
local bitor = bit32.bor
local bitxor = bit32.bxor
local bit = bit32.btest
local string_lower = string.lower
local time = wg.time
local WriteFile = wg.writefile

local function mapped_paragraphs(document)
	local position, number = 0, 0
	return function()
		local size = document._textbuffer:size()
		if position > size then return nil end
		if position == size and size > 0 and
				document._textbuffer:slice(size-1, 1) ~= "\n" then
			return nil
		end
		local start = position
		local newline = document._textbuffer:find(start, 10)
		local finish = newline or size
		if finish-start > 16*1024*1024 then
			error("mapped exporter paragraph exceeds the 16 MiB safety limit")
		end
		local text = document._textbuffer:slice(start, finish-start)
		if text:sub(-1) == "\r" then text = text:sub(1, -2) end
		position = newline and (newline+1) or (size+1)
		local style = document:largeParagraphStyleAt(start)
		local boundaries = {start, finish}
		for _, span in ipairs(document:ensureDocumentIndex().characterStyles or {}) do
			if span.finish > start and span.start < finish then
				boundaries[#boundaries+1] = math.max(start, span.start)
				boundaries[#boundaries+1] = math.min(finish, span.finish)
			end
		end
		table.sort(boundaries)
		local styled, previous = {}, nil
		for _, boundary in ipairs(boundaries) do
			if previous and boundary > previous then
				local mask = document:largeCharacterStyleAt(previous)
				if mask ~= 0 then styled[#styled+1] = wg.createstylebyte(mask) end
				styled[#styled+1] = document._textbuffer:slice(previous, boundary-previous)
			end
			previous = boundary
		end
		local paragraph = CreateParagraph(style, table.concat(styled))
		if style == "LN" then number = number + 1; paragraph.number = number end
		return paragraph
	end
end

-- Renders the document by calling the appropriate functions on the cb
-- table.

function ExportFileUsingCallbacks(document, cb)
	if not document:usesTextBuffer() then document:renumber() end
	cb.prologue()

	local listmode= nil
	local rawmode = false
	local italic, underline, bold
	local olditalic, oldunderline, oldbold
	local firstword
	local wordbreak
	local emptyword

	local wordwriter = function (style, text)
		italic = bit(style, ITALIC)
		underline = bit(style, UNDERLINE)
		bold = bit(style, BOLD)

		local writer
		if rawmode then
			writer = cb.rawtext
		else
			writer = cb.text
		end

		-- Underline is stopping, so do so *before* the space
		if wordbreak and not underline and oldunderline then
			cb.underline_off()
		end

		if wordbreak then
			writer(' ')
			wordbreak = false
		end

		if not wordbreak and oldunderline then
			cb.underline_off()
		end
		if oldbold then
			cb.bold_off()
		end
		if olditalic then
			cb.italic_off()
		end
		if italic then
			cb.italic_on()
		end
		if bold then
			cb.bold_on()
		end
		if underline then
			cb.underline_on()
		end
		writer(text)

		emptyword = false
		olditalic = italic
		oldunderline = underline
		oldbold = bold
	end

	local nextparagraph
	if document:usesTextBuffer() then
		nextparagraph = mapped_paragraphs(document)
	else
		local index = 0
		nextparagraph = function() index=index+1; return document[index] end
	end
	while true do
		local paragraph = nextparagraph()
		if not paragraph then break end
		local name = paragraph.style
		local style = documentStyles[name]

		if listmode and not style.list then
			cb.list_end(listmode)
			listmode = nil
		end
		if not listmode and style.list then
			cb.list_start(name)
			listmode = name
		end

		rawmode = (name == "RAW")

		cb.paragraph_start(paragraph)

		if (#paragraph == 1) and (#paragraph[1] == 0) then
			cb.notext()
		else
			firstword = true
			wordbreak = false
			olditalic = false
			oldunderline = false
			oldbold = false

			for wn, word in ipairs(paragraph) do
				if firstword then
					firstword = false
				else
					wordbreak = true
				end

				emptyword = true
				italic = false
				underline = false
				bold = false
				ParseWord(word, 0, wordwriter) -- FIXME
				if emptyword then
					wordwriter(0, "")
				end
			end

			if underline then
				cb.underline_off()
			end
			if bold then
				cb.bold_off()
			end
			if italic then
				cb.italic_off()
			end
		end

		cb.paragraph_end(paragraph)
	end
	if listmode then
		cb.list_end(listmode)
	end
	cb.epilogue()
end

-- Prompts the user to export a document, and then calls
-- exportcb(writer, document) to actually do the work.

function ExportFileWithUI(filename, title, extension, callback)
	if not filename then
		filename = currentDocument.name
		if filename then
			if not filename:find("%..-$") then
				filename = filename .. extension
			else
				filename = filename:gsub("%..-$", extension)
			end
		else
			filename = "(unnamed)"
		end

		filename = FileBrowser(title, "Export as:", true,
			filename)
		if not filename then
			return false
		end
		assert(filename)
		if filename:find("/[^.]*$") then
			filename = filename .. extension
		end
	end

	ImmediateMessage("Exporting "..filename.."...")
	local output, e = wg.openwriter(filename)
	if not output then
		ModalMessage(nil, "Unable to open the output file "..e..".")
		QueueRedraw()
		return false
	end
	local writer = function(...) return output:write(...) end
	local ok, exporterror = pcall(callback, writer, currentDocument)
	local closed, closeerror = output:close()
	if not ok or not closed then
		ModalMessage(nil, "Unable to export the output file: "..
			tostring(exporterror or closeerror))
		QueueRedraw()
		return false
	end

	QueueRedraw()
	return true
end

--- Converts a document into a local string.

function ExportToString(document, callback)
	if document:usesTextBuffer() then
		error("refusing to materialise a mapped text document as one Lua string")
	end
	local ss = {}
	local writer = function(...)
		for _, s in ipairs({...}) do
			ss[#ss+1] = s
		end
	end

	callback(writer, document)

	return table.concat(ss)
end
