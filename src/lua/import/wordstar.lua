--!nonstrict
-- WordStar document importer.

local BOLD = wg.BOLD
local ITALIC = wg.ITALIC
local UNDERLINE = wg.UNDERLINE
local WORDSTAR_ENCODING = "CP437"

local WS = {
	EOF = 0x1a,
	EXTENDED_CHARACTER = 0x1b,
	SYMMETRIC_BLOCK = 0x1d,
	HARD_RETURN = 0x0d,
	LINE_FEED = 0x0a,
	SOFT_RETURN = 0x8d,
	HIGH_BIT = 0x80,
	STYLE_BOLD = 0x02,
	STYLE_DOUBLE_STRIKE = 0x04,
	STYLE_UNDERLINE = 0x13,
	STYLE_ITALIC = 0x19,
	STYLE_STRIKE = 0x18,
	BINDING_SPACE = 0x0f,
	SOFT_HYPHEN_INACTIVE = 0x1e,
	SOFT_HYPHEN_ACTIVE = 0x1f,
	BLOCK_FOOTNOTE = 0x03,
	BLOCK_ENDNOTE = 0x04,
	BLOCK_TAB = 0x09,
	BLOCK_PAGE_BREAK = 0x0b,
	BLOCK_PARAGRAPH_STYLE = 0x11,
	PARAGRAPH_HEADER = 0x02,
	PARAGRAPH_SUBHEADING = 0x03,
	PARAGRAPH_TITLE = 0x05,
	BYTE_RADIX = 0x100,
	BLOCK_LENGTH_LOW_OFFSET = 1,
	BLOCK_LENGTH_HIGH_OFFSET = 2,
	BLOCK_TYPE_OFFSET = 3,
	BLOCK_SUBTYPE_OFFSET = 4,
	BLOCK_STORAGE_OVERHEAD = 3,
}

local paragraphStyles = {
	[WS.PARAGRAPH_TITLE] = "H1",
	[WS.PARAGRAPH_HEADER] = "H2",
	[WS.PARAGRAPH_SUBHEADING] = "H3",
}

function Cmd.ImportWordStarString(data)
	local document = CreateDocument()
	local importer = CreateImporter(document)
	importer:reset()
	local activeStyles = {}
	local paragraphStyle = "P"
	local atLineStart = true
	local skippingDotCommand = false
	local continuesAcrossSoftReturn = false
	local lastCharacterWasHyphen = false
	local hasWordStarReturns = data:find(string.char(WS.HARD_RETURN), 1, true) or
		data:find(string.char(WS.SOFT_RETURN), 1, true)

	local function toggleStyle(control, style)
		if activeStyles[control] then
			importer:style_off(style)
			activeStyles[control] = nil
		else
			importer:style_on(style)
			activeStyles[control] = true
		end
	end

	local function emit(text)
		for character in text:gmatch(".") do
			if character:match("%s") then
				importer:flushword()
				lastCharacterWasHyphen = false
			else
				importer:text(character)
				lastCharacterWasHyphen = character == "-"
			end
		end
	end

	local function finishParagraph()
		if not skippingDotCommand then importer:flushparagraph(paragraphStyle) end
		paragraphStyle = "P"
		atLineStart = true
		skippingDotCommand = false
	end

	local position = 1
	while position <= #data do
		local byte = data:byte(position)
		if byte == WS.EOF then
			break
		elseif byte == WS.SYMMETRIC_BLOCK and
			position + WS.BLOCK_LENGTH_HIGH_OFFSET <= #data then
			local length = data:byte(position + WS.BLOCK_LENGTH_LOW_OFFSET) +
				data:byte(position + WS.BLOCK_LENGTH_HIGH_OFFSET) * WS.BYTE_RADIX
			local blockType = data:byte(position + WS.BLOCK_TYPE_OFFSET)
			if blockType == WS.BLOCK_PARAGRAPH_STYLE then
				paragraphStyle = paragraphStyles[
					data:byte(position + WS.BLOCK_SUBTYPE_OFFSET)] or paragraphStyle
			elseif blockType == WS.BLOCK_TAB then
				importer:flushword()
			elseif blockType == WS.BLOCK_PAGE_BREAK then
				finishParagraph()
			end
			position = position + length + WS.BLOCK_STORAGE_OVERHEAD
		elseif byte == WS.EXTENDED_CHARACTER and position < #data then
			-- WordStar escapes a literal extended byte with ESC.
			emit(wg.transcodefrom(data:sub(position + 1, position + 1),
				WORDSTAR_ENCODING))
			position = position + 2
		elseif byte == WS.HARD_RETURN then
			finishParagraph()
			position = position + 1
		elseif byte == WS.LINE_FEED then
			-- WordStar pads both hard and soft returns with LF. A printable-only
			-- .ws fixture may use Unix line endings, so retain that safe fallback.
			if not hasWordStarReturns then finishParagraph() end
			position = position + 1
		elseif byte == WS.SOFT_RETURN then
			if not continuesAcrossSoftReturn and not lastCharacterWasHyphen then
				importer:flushword()
			end
			continuesAcrossSoftReturn = false
			lastCharacterWasHyphen = false
			position = position + 1
		elseif byte == WS.STYLE_BOLD or byte == WS.STYLE_DOUBLE_STRIKE then
			toggleStyle(byte, BOLD)
			position = position + 1
		elseif byte == WS.STYLE_ITALIC then
			toggleStyle(byte, ITALIC)
			position = position + 1
		elseif byte == WS.STYLE_UNDERLINE then
			toggleStyle(byte, UNDERLINE)
			position = position + 1
		elseif byte == WS.BINDING_SPACE then
			importer:flushword()
			position = position + 1
		elseif byte == WS.SOFT_HYPHEN_ACTIVE then
			importer:text("-")
			continuesAcrossSoftReturn = true
			lastCharacterWasHyphen = true
			position = position + 1
		elseif byte == WS.SOFT_HYPHEN_INACTIVE then
			continuesAcrossSoftReturn = true
			position = position + 1
		elseif byte < 0x20 then
			position = position + 1
		else
			local character = string.char(byte >= WS.HIGH_BIT and
				(byte - WS.HIGH_BIT) or byte)
			if atLineStart and character == "." then
				skippingDotCommand = true
			end
			atLineStart = false
			if not skippingDotCommand then emit(character) end
			position = position + 1
		end
	end
	if not atLineStart then finishParagraph() end
	if #document > 1 then document:deleteParagraphAt(1) end
	return document
end

function Cmd.ImportWordStarFile(filename)
	return ImportFileWithUI(filename, "Import WordStar File", Cmd.ImportWordStarString)
end
