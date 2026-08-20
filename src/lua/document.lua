-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local table_remove = table.remove
local table_insert = table.insert
local table_concat = table.concat
local Write = wg.write
local WriteStyled = wg.writestyled
local ClearToEOL = wg.cleartoeol
local SetNormal = wg.setnormal
local SetBold = wg.setbold
local SetUnderline = wg.setunderline
local SetReverse = wg.setreverse
local SetDim = wg.setdim
local GetStringWidth = wg.getstringwidth
local GetBytesOfCharacter = wg.getbytesofcharacter
local GetWordText = wg.getwordtext
local BOLD = wg.BOLD
local ITALIC = wg.ITALIC
local UNDERLINE = wg.UNDERLINE
local REVERSE = wg.REVERSE
local BRIGHT = wg.BRIGHT
local DIM = wg.DIM

documentStyles = {}

local Document = {}
Document.__index = Document
_G.Document = Document

function Document.cursor(self)
	return { self.cp, self.cw, self.co }
end

function Document.appendParagraph(self, p)
	self[#self+1] = p
end

function Document.insertParagraphBefore(self, paragraph, pn)
	table.insert(self, pn, paragraph)
end

function Document.deleteParagraphAt(self, pn)
	table.remove(self, pn)
end

function Document.wrap(self, width)
	self._wrapwidth = width
end

function Document.getMarks(self)
	if not self.mp then
		return
	end

	local mp1 = assert(self.mp)
	local mw1 = assert(self.mw)
	local mo1 = assert(self.mo)
	local mp2 = self.cp
	local mw2 = self.cw
	local mo2 = self.co

	if (mp1 > mp2) or
	   ((mp1 == mp2) and
		   ((mw1 > mw2) or ((mw1 == mw2) and (mo1 > mo2)))
	   ) then
		return mp2, mw2, mo2, mp1, mw1, mo1
	end

	return mp1, mw1, mo1, mp2, mw2, mo2
end

-- calculate space above this paragraph
function Document.spaceAbove(self, pn)
	local paragraph = self[pn]
	local paragraphabove = self[pn - 1]

	local sa = documentStyles[paragraph.style].above or 0 -- FIXME
	local sb = 0
	if paragraphabove then
		sb = documentStyles[paragraphabove.style].below or 0 -- FIXME
	end

	if (sa > sb) then
		return sa
	else
		return sb
	end
end

-- calculate space below this paragraph
function Document.spaceBelow(self, pn)
	local paragraph = self[pn]
	local paragraphbelow = self[pn + 1]

	local sb = documentStyles[paragraph.style].below or 0 -- FIXME
	local sa = 0
	if paragraphbelow then
		sa = documentStyles[paragraphbelow.style].above or 0 -- FIXME
	end

	if (sa > sb) then
		return sa
	else
		return sb
	end
end

function Document.touch(self)
	FireEvent("DocumentModified", self)
end

function Document.renumber(self)
	local wc = 0
	local pn = 1

	for _, p in ipairs(self) do
		wc = wc + #p

		local style = documentStyles[p.style]
		if style.numbered then
			p.number = pn
			pn = pn + 1
		elseif not style.list then
			pn = 1
		end
	end

	self.wordcount = wc
end

-- Returns how many screen spaces a portion of a string takes up.
function GetWidthFromOffset(s, o)
	return GetStringWidth(s:sub(1, o-1))
end

-- Returns the offset into a string needed for a screen width.
function GetOffsetFromWidth(s, x)
		local len = #s
		local o = 1
		while (o <= len) do
			if (x == 0) then
				return o
			end

			local charlen = GetBytesOfCharacter(string.byte(s, o))
			local char = s:sub(o, o+charlen-1)
			local ww = GetStringWidth(char)
			if (ww > x) then
				return o
			end

			x = x - ww
			o = o + charlen
		end

		return len + 1
end

function GetWordSimpleText(s)
	s = GetWordText(s)
	s = UnSmartquotify(s)
	s = s:gsub('[`~#&^$"<>]+', "")
	s = s:gsub("^[.'([{]+", "")
	s = s:gsub("[',.!?:;)%]}]+$", "")
	return s
end

function OnlyFirstCharIsUppercase(s)
    -- Return true if only first character is uppercase
    local first_char = s:sub(0, 1)
    if first_char:upper() == first_char then
        local remaining_chars = s:sub(2, s:len())
        if remaining_chars:lower() == remaining_chars then
            return true
        end
    end
    return false
end

function UpdateDocumentStyles()
	local plaintext =
	{
		desc = "Plain text",
		name = "P",
	}

	if WantParagraphSpacing() then
		plaintext.above = 1
		plaintext.below = 1
	else
		plaintext.above = 0
		plaintext.below = 0
	end

	if WantFirstLineIndent() then
		plaintext.firstindent = 4
	else
		plaintext.firstindent = 0
	end

	local styles=
	{
		plaintext,
		{
			desc = "Heading #1",
			name = "H1",
			above = 3,
			below = 1,
			nextstyle = "P",
		},
		{
			desc = "Heading #2",
			name = "H2",
			above = 2,
			below = 1,
			nextstyle = "P",
		},
		{
			desc = "Heading #3",
			name = "H3",
			above = 1,
			below = 1,
			nextstyle = "P",
		},
		{
			desc = "Heading #4",
			name = "H4",
			above = 1,
			below = 1,
			nextstyle = "P",
		},
		{
			desc = "Indented text",
			name = "Q",
			indent = 4,
			above = 1,
			below = 1,
		},
		{
			desc = "Footnote or endnote",
			name = "N",
			above = 0,
			below = 0,
		},
		{
			desc = "Figure or table caption",
			name = "C",
			above = 0,
			below = 1,
		},
		{
			desc = "List item with bullet",
			name = "LB",
			above = 1,
			below = 1,
			indent = 4,
			bullet = "-",
			list = true,
		},
		{
			desc = "List item with number",
			name = "LN",
			above = 1,
			below = 1,
			indent = 4,
			numbered = true,
			list = true,
		},
		{
			desc = "List item without bullet",
			name = "L",
			above = 1,
			below = 1,
			indent = 4,
			list = true,
		},
		{
			desc = "Indented text, run together",
			name = "V",
			indent = 4,
			above = 0,
			below = 0
		},
		{
			desc = "Preformatted text",
			name = "PRE",
			indent = 4,
			above = 0,
			below = 0
		},
		{
			desc = "Raw data exported to output file",
			name = "RAW",
			indent = 0,
			above = 0,
			below = 0
		}
	}

	for _, s in ipairs(styles) do
		styles[s.name] = s
	end

	documentStyles = styles
end

function CreateDocument()
	local d =
	{
		_wrapwidth = 0,
		viewmode = 1,
		margin = 0,
		cp = 1,
		cw = 1,
		co = 1,
		pageLayout = {
			profile = "Custom",
			pageWidthCm = 21.0,
			pageHeightCm = 29.7,
			marginTopCm = 2.5,
			marginRightCm = 2.5,
			marginBottomCm = 2.5,
			marginLeftCm = 2.5,
			fontSizePt = 12,
			lineSpacing = 1.15,
			specialFontSizePt = 10,
			specialLineSpacing = 1.0,
			longQuoteIndentCm = 4.0,
		},
	}

	local dd = (setmetatable(d, Document))

	local p = CreateParagraph("P", {""})
	dd:appendParagraph(p)
	return dd
end
