-- © 2023 David Given.
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

local Paragraph = {}
Paragraph.__index = Paragraph
_G.Paragraph = Paragraph

local stylemarkup =
{
	["H1"] = ITALIC + BRIGHT + BOLD + UNDERLINE,
	["H2"] = BRIGHT + BOLD + UNDERLINE,
	["H3"] = ITALIC + BRIGHT + BOLD,
	["H4"] = BRIGHT + BOLD
}

function GetParagraphStyleMarkup(style)
	return stylemarkup[style] or 0
end

function Paragraph.__iter(self)
	local function iter(a, i)
      i = i + 1
      local v = a[i]
      if v then
        return i, v
      end
	  return nil, nil
    end

	return iter, self, 0
end

function CreateParagraph(style, ...)
	if type(style) ~= "string" then
		error("paragraph style is not a string")
	end
	local words = {
		style = style
	}

	for _, t in ipairs({...}) do
		if type(t) == "table" then
			for _, w in ipairs(t) do
				words[#words+1] = w
			end
		elseif type(t) == "string" then
			words[#words+1] = t
		end
	end

	return (setmetatable(words, Paragraph))
end

function Paragraph.copy(self)
	local words= {}

	for _, w in self:__iter() do
		words[#words+1] = w
	end

	return CreateParagraph(self.style, words)
end

function Paragraph.wrap(self, width)
	width = width or currentDocument._wrapwidth or 80
	assert(width)

	if not self._wrapdata or self._wrapdata.wrapwidth ~= width then
		local wrapdata = {}
		wrapdata.wrapwidth = width

		-- Recompute sentences.

		local issentence = true
		local sentences = {}
		for wn, word in self:__iter() do
			if issentence then
				sentences[wn] = true
				issentence = false
			end

			if word:find("[^%a]$") then
				issentence = true
			end
		end
		sentences[#self] = true
		wrapdata.sentences = sentences

		-- Recompute line wrapping.

		local lines = {}
		local line = {wn = 1}
		local w = 0
		local xs = {}
		local fullstopspaces = WantFullStopSpaces()

		width = width - self:getIndentOfLine(1)
		local function fragmentend(word, start, limit)
			local finish = start
			local used = 0
			while finish <= #word do
				local charlen = GetBytesOfCharacter(string.byte(word, finish))
				local nextfinish = finish + charlen
				local charwidth = GetStringWidth(word:sub(finish, nextfinish - 1))
				if (used + charwidth > limit) and (finish > start) then break end
				used = used + charwidth
				finish = nextfinish
			end
			return finish
		end

		for wn, word in ipairs(self) do
			-- get width of word (including space)
			local ww = GetStringWidth(word) + 1
			local available = math.max(width, 1)

			-- A single uninterrupted word can be wider than the paper (most
			-- commonly while key repeat is held). Represent it as visual
			-- fragments so rendering never escapes the paper. This does not
			-- alter the stored word or exported text.
			local hyphenate = GetWordWrapMode() == "Hyphenate"
			local remaining = width - w
			local splitatend = hyphenate and (#line > 0) and
				((ww - 1) >= remaining) and (remaining >= 2)

			if splitatend then
				local finish = fragmentend(word, 1, remaining - 1)
				xs[wn] = w
				line[#line+1] = wn
				line.trailingfragment = {
					start = 1, finish = finish, hyphen = true,
				}
				lines[#lines+1] = line
				if #lines == 1 then
					width = width + self:getIndentOfLine(1) - self:getIndentOfLine(2)
				end

				local start = finish
				while start <= #word do
					local contentlimit = math.max(width - 1, 1)
					finish = fragmentend(word, start, contentlimit)
					local continued = finish <= #word
					local fragmentline = { wn = wn, wn }
					fragmentline.fragment = {
						start = start, finish = finish,
						hyphen = continued,
					}
					lines[#lines+1] = fragmentline
					start = finish
				end
				line = {wn = wn + 1}
				w = 0
			elseif (ww - 1) > available then
				if #line > 0 then
					lines[#lines+1] = line
					if #lines == 1 then
						width = width + self:getIndentOfLine(1) - self:getIndentOfLine(2)
					end
				end

				local start = 1
				while start <= #word do
					local limit = math.max(width, 1)
					local contentlimit = math.max(limit - (hyphenate and 1 or 0), 1)
					local finish = fragmentend(word, start, contentlimit)

					local continued = finish <= #word
					local fragmentline = { wn = wn, wn }
					fragmentline.fragment = {
						start = start,
						finish = finish,
						hyphen = continued and hyphenate,
					}
					lines[#lines+1] = fragmentline
					start = finish
				end

				line = {wn = wn + 1}
				w = 0
				xs[wn] = 0
			else
				-- add an extra space if the user asked for it
				if fullstopspaces and word:find("%.$") then
					ww = ww + 1
				end

				xs[wn] = w
				w = w + ww
				-- Do not wrap one keypress early merely because the reserved
				-- separator reaches the boundary. Hyphenation above gets first
				-- chance when the word itself reaches the remaining space.
				local overflow = hyphenate and (w > width) or
					(not hyphenate and (w >= width))
				if overflow and (#line > 0) then
					lines[#lines+1] = line
					if #lines == 1 then
						width = width + self:getIndentOfLine(1) - self:getIndentOfLine(2)
					end
					line = {wn = wn}
					w = ww
					xs[wn] = 0
				end

				line[#line+1] = wn
			end
		end

		if (#line > 0) then
			lines[#lines+1] = line
		end

		wrapdata.lines = lines
		wrapdata.xs = xs
		self._wrapdata = wrapdata
		return wrapdata
	else
		return self._wrapdata
	end
end

function Paragraph.renderLine(self, line, x, y)
	local cstyle = stylemarkup[self.style] or 0
	local ostyle = 0
	local wd = self._wrapdata
	assert(wd)

	for _, wn in ipairs(line) do
		local w = self[wn]
		local wordx = wd.xs[wn]
		local fragment = line.fragment
		if line.trailingfragment and wn == line[#line] then
			fragment = line.trailingfragment
		end
		if fragment then
			w = w:sub(fragment.start, fragment.finish - 1)
			if line.fragment then
				wordx = 0
			end
			if fragment.hyphen then
				w = w.."-"
			end
		end

		local payload = {
			word = w,
			ostyle = ostyle,
			cstyle = cstyle,
			firstword = wd.sentences[wn]
		}
		FireEvent("DrawWord", payload)

		ostyle = WriteStyled(
			x+wordx, y,
			payload.word,
			payload.ostyle, 0, 0, payload.cstyle)
	end
end

function Paragraph.renderMarkedLine(self, line, x, y, width, pn)
	width = width or (ScreenWidth - x)

	local lwn= line.wn
	local mp1, mw1, mo1, mp2, mw2, mo2 = currentDocument:getMarks()

	local cstyle = stylemarkup[self.style] or 0
	local ostyle = 0
	for i, w in ipairs(line) do
		local s, e

		local wn = lwn + i - 1

		if (pn < mp1) or (pn > mp2) then
			s = 0
		elseif (pn > mp1) and (pn < mp2) then
			s = 1
		else
			if (pn == mp1) and (pn == mp2) then
				if (wn == mw1) and (wn == mw2) then
					s = mo1
					e = mo2
				elseif (wn == mw1) then
					s = mo1
				elseif (wn == mw2) then
					s = 1
					e = mo2
				elseif (wn > mw1) and (wn < mw2) then
					s = 1
				end
			elseif (pn == mp1) then
				if (wn > mw1) then
					s = 1
				elseif (wn == mw1) then
					s = mo1
				end
			else
				s = 1
				if (wn > mw2) then
					s = 0
				elseif (wn == mw2) then
					e = mo2
				end
			end
		end

		local wd = self:wrap()
		local word = self[w]
		local wordx = wd.xs[w]
		local fragment = line.fragment
		if line.trailingfragment and w == line[#line] then
			fragment = line.trailingfragment
		end
		if fragment then
			local fs = fragment.start
			local fe = fragment.finish
			word = word:sub(fs, fe - 1)
			wordx = 0

			-- Selection offsets refer to the complete stored word. Translate
			-- them into this visual fragment; a mouse click temporarily enables
			-- marked rendering even for a zero-width selection.
			if s and (s > 0) then
				local selectionend = e or (#self[w] + 1)
				local intersectionstart = math.max(s, fs)
				local intersectionend = math.min(selectionend, fe)
				if intersectionstart <= intersectionend then
					s = intersectionstart - fs + 1
					e = intersectionend - fs + 1
				else
					s, e = 0, 0
				end
			end

			if fragment.hyphen then
				word = word.."-"
			end
		end
		local payload = {
			word = word,
			ostyle = ostyle,
			cstyle = cstyle,
			firstword = wd.sentences[wn]
		}
		FireEvent("DrawWord", payload)

		ostyle = WriteStyled(x+wordx, y, payload.word,
			payload.ostyle, s, e, payload.cstyle)
	end
end

-- returns: line number, word number in line
function Paragraph.getLineOfWord(self, wn, co)
	local wd = self:wrap()
	for ln, l in ipairs(wd.lines) do
		local fragment = l.fragment
		if l.trailingfragment and l[#l] == wn then
			fragment = l.trailingfragment
		end
		if fragment and ((l[1] == wn) or (l[#l] == wn)) then
			-- fragment.finish is the first byte belonging to the next
			-- fragment, so a cursor exactly on that boundary must follow the
			-- text onto the next visual line. Only the final fragment owns the
			-- position immediately after the word.
			local islast = fragment.finish > #self[wn]
			if not co or
				(co >= fragment.start and co < fragment.finish) or
				(islast and co == #self[wn] + 1) then
				return ln, 1
			end
		else
			for i, wordnumber in ipairs(l) do
				if wordnumber == wn then
					return ln, i
				end
			end
		end
	end

	error("word out of range")
end

-- returns: number of characters
function Paragraph.getIndentOfLine(self, ln)
	local indent
	if (ln == 1) then
		indent = documentStyles[self.style].firstindent
	end
	local indent = indent or documentStyles[self.style].indent or 0
	return indent
end

-- returns: word number
function Paragraph.getWordOfLine(self, ln)
	local wd = self:wrap()
	return wd.lines[ln].wn
end

-- returns: X offset, line number, word number in line
function Paragraph.getXOffsetOfWord(self, wn, co)
	local wd = self:wrap()
	local ln, wordinline = self:getLineOfWord(wn, co)
	local line = wd.lines[assert(ln)]
	local x = wd.xs[wn]
	local fragment = line.fragment
	if line.trailingfragment and line[#line] == wn then
		fragment = line.trailingfragment
	end
	if fragment then
		local prefixwidth = GetStringWidth(self[wn]:sub(1, fragment.start - 1))
		if line.fragment then
			x = -prefixwidth
		else
			x = x - prefixwidth
		end
	end
	return x, ln, assert(wordinline)
end

function Paragraph.sub(self, start, count)
	if not count then
		count = #self - start + 1
	else
		count = math.min(count, #self - start + 1)
	end
	assert(count)

	local t = {}
	for i = start, start+count-1 do
		t[#t+1] = self[i]
	end
	return t
end

-- return an unstyled string containing the contents of the paragraph.
function Paragraph.asString(self)
	local s = {}
	for _, w in self:__iter() do
		s[#s+1] = GetWordText(w)
	end

	return table_concat(s, " ")
end
