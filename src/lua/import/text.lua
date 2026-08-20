--!nonstrict
-- © 2008-2013 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local ITALIC = wg.ITALIC
local UNDERLINE = wg.UNDERLINE
local ParseWord = wg.parseword
local WriteU8 = wg.writeu8
local bitand = bit32.band
local bitor = bit32.bor
local bitxor = bit32.bxor
local bit = bit32.btest
local string_char = string.char
local string_find = string.find
local string_sub = string.sub
local table_concat = table.concat

-----------------------------------------------------------------------------
-- The importer itself.

function Cmd.ImportTextString(data)
	local document = CreateDocument()
	local fp = CreateIStream(data)
	for rawline in fp:lines() do
		local l = CanonicaliseString(rawline)
		l = l:gsub("%c+", "")
		local p = CreateParagraph("P", ParseStringIntoWords(l))
		document:appendParagraph(p)
	end

	-- Remove the blank paragraph at the beginning of the document.

	if (#document > 1) then
		document:deleteParagraphAt(1)
	end

	return document
end

function Cmd.ImportTextFile(filename)
	if not filename then
		filename = FileBrowser("Import Text File", "Import from:", false)
		if not filename then return false end
	end
	local info = wg.stat(filename)
	local threshold = tonumber(GlobalSettings.large_file_threshold) or
		(64 * 1024 * 1024)
	threshold = math.max(1024 * 1024, threshold)
	if info and info.mode == "file" and info.size >= threshold then
		ImmediateMessage("Opening large text document...")
		local document, e = CreateTextBufferDocument(filename)
		if not document then
			ModalMessage("Cannot open text document", e or "Unknown error")
			return false
		end
		return AddImportedDocument(filename, document)
	end
	return ImportFileWithUI(filename, "Import Text File", Cmd.ImportTextString)
end
