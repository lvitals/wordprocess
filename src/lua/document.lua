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

	-- Every paragraph's cached line count is now stale, so the scrollbar's
	-- cached document total and topline anchor (see computelinerange() in
	-- redraw.lua) are too.
	self._totallines = nil
	self._toplineanchorp = nil
	self._toplineanchorv = nil
end

function Document.usesTextBuffer(self)
	return self._textbuffer ~= nil
end

function Document.textLineBounds(self, position)
	position = position or self._textpos
	local start = self._textbuffer:rfind(0, 10, position)
	start = start and (start + 1) or 0
	local finish = self._textbuffer:find(position, 10)
	finish = finish or self._textbuffer:size()
	local contentfinish = finish
	if contentfinish > start and self._textbuffer:slice(contentfinish - 1, 1) == "\r" then
		contentfinish = contentfinish - 1
	end
	return start, contentfinish, finish
end

function Document.moveTextLine(self, direction)
	local start, _, finish = self:textLineBounds()
	local column = self._textpos - start
	if direction > 0 then
		if finish >= self._textbuffer:size() then return false end
		local nextstart = finish + 1
		local nextfinish = self._textbuffer:find(nextstart, 10) or self._textbuffer:size()
		self._textpos = math.min(nextstart + column, nextfinish)
	else
		if start == 0 then return false end
		local previousend = start - 1
		local previousstart = self._textbuffer:rfind(0, 10, previousend)
		previousstart = previousstart and (previousstart + 1) or 0
		self._textpos = math.min(previousstart + column, previousend)
	end
	if self._textline then
		self._textline = self._textline + (direction > 0 and 1 or -1)
	end
	local target_start = self:textLineBounds(self._textpos)
	if target_start < (self._texttop or 0) then
		self._texttop = target_start
		self._texttopline = self._textline
	elseif self._textbottom and target_start >= self._textbottom then
		local oldtop = self._texttop or 0
		local newline = self._textbuffer:find(oldtop, 10)
		self._texttop = newline and (newline + 1) or target_start
		if self._texttopline then self._texttopline = self._texttopline + 1 end
	end
	QueueRedraw()
	return true
end

-- Scrolls _texttop by whole logical lines, if needed, so the cursor's
-- current line falls inside a `rows`-row-tall viewport starting at
-- _texttop. moveTextLine (above) keeps _texttop in sync as it moves the
-- cursor one line at a time, but edits that move the cursor by joining or
-- splitting lines (Backspace/Delete across a line boundary, typing a
-- newline, pasting, undo/redo) go through deleteTextRange/insert instead
-- and don't -- so the redraw path calls this before drawing to reconcile
-- the two, exactly like a navigation command would have.
function Document.ensureTextCursorVisible(self, rows)
	if not rows or rows < 1 then return end
	local linestart = self:textLineBounds()
	local top = self._texttop or 0
	if linestart < top then
		self._texttop = linestart
	else
		local offset, distance = top, 0
		while offset < linestart do
			local newline = self._textbuffer:find(offset, 10)
			if not newline then break end
			offset = newline + 1
			distance = distance + 1
		end
		if distance < rows then return end
		offset = top
		for _ = 1, distance - rows + 1 do
			offset = self._textbuffer:find(offset, 10) + 1
		end
		self._texttop = offset
	end
	self._texttopline = self:getLineAtPosition(self._texttop)
end

function Document.previousTextPosition(self, position)
	position = position or self._textpos
	if position == 0 then return nil end
	local candidate = position - 1
	while candidate > 0 do
		local byte = self._textbuffer:slice(candidate, 1):byte()
		if byte < 0x80 or byte >= 0xc0 then break end
		candidate = candidate - 1
	end
	return candidate
end

function Document.nextTextPosition(self, position)
	position = position or self._textpos
	local size = self._textbuffer:size()
	if position >= size then return nil end
	local byte = self._textbuffer:slice(position, 1):byte()
	local length = byte < 0x80 and 1 or
		(byte < 0xe0 and 2 or (byte < 0xf0 and 3 or (byte < 0xf8 and 4 or 1)))
	return math.min(size, position + length)
end

function Document.textCellOffset(self, start, finish)
	local width = 0
	local position = start
	while position < finish do
		local nextposition = self:nextTextPosition(position) or finish
		nextposition = math.min(nextposition, finish)
		width = width + GetStringWidth(
			self._textbuffer:slice(position, nextposition - position))
		position = nextposition
	end
	return width
end

-- Translate terminal-cell coordinates to byte-safe UTF-8 boundaries. Wide
-- and combining characters are never split, even by horizontal scrolling.
function Document.textViewport(self, start, finish, firstcell, cellwidth)
	local position, cells = start, 0
	while position < finish and cells < firstcell do
		local nextposition = self:nextTextPosition(position) or finish
		local width = GetStringWidth(
			self._textbuffer:slice(position, nextposition - position))
		if cells + width > firstcell then break end
		cells = cells + width
		position = nextposition
	end
	local displaystart = position
	local used = 0
	while position < finish do
		local nextposition = self:nextTextPosition(position) or finish
		local width = GetStringWidth(
			self._textbuffer:slice(position, nextposition - position))
		if used + width > cellwidth then break end
		used = used + width
		position = nextposition
	end
	return displaystart, position, used
end

function Document.textSelection(self)
	if self._textmark == nil then return nil end
	return math.min(self._textmark, self._textpos),
		math.max(self._textmark, self._textpos)
end

function Document.ensureDocumentIndex(self)
	-- Migrate the historical storage-size-specific field in memory. It is
	-- deliberately removed so subsequent saves contain only the neutral name.
	self.documentIndex = self.documentIndex or self.largeDocument or {}
	self.largeDocument = nil
	self.documentIndex.characterStyles = self.documentIndex.characterStyles or {count=0}
	self.documentIndex.paragraphStyles = self.documentIndex.paragraphStyles or {count=0}
	-- Version 1 called logical text lines "paragraphs". They share newline
	-- checkpoints, so migrate rather than retaining duplicate indexes.
	self.documentIndex.lineCount = self.documentIndex.lineCount or
		self.documentIndex.paragraphCount
	self.documentIndex.lineIndexStride = self.documentIndex.lineIndexStride or
		self.documentIndex.paragraphIndexStride
	self.documentIndex.lineOffsets = self.documentIndex.lineOffsets or
		self.documentIndex.paragraphOffsets
	self.documentIndex.paragraphCount = nil
	self.documentIndex.paragraphIndexStride = nil
	self.documentIndex.paragraphOffsets = nil
	return self.documentIndex
end

function Document.getLineCount(self)
	if not self:usesTextBuffer() then return #self end
	return self:ensureDocumentIndex().lineCount
end

function Document.getLineAtPosition(self, position)
	if not self:usesTextBuffer() then
		return math.max(1, math.min(position or self.cp, #self)), true
	end
	position = math.max(0, math.min(position or self._textpos,
		self._textbuffer:size()))
	if position == self._textpos and self._textline then return self._textline, true end
	local index = self:ensureDocumentIndex()
	local offsets = index.lineOffsets
	local stride = index.lineIndexStride
	if not index.lineCount or not offsets or not stride then return nil, false end
	local low, high, checkpoint = 1, #offsets, 1
	while low <= high do
		local middle = math.floor((low + high) / 2)
		if offsets[middle] <= position then checkpoint, low = middle, middle + 1
		else high = middle - 1 end
	end
	local numbers = index.lineNumbers
	local line = numbers and numbers[checkpoint] or
		((checkpoint - 1) * stride + 1)
	local scan = offsets[checkpoint]
	while scan < position do
		local newline = self._textbuffer:find(scan, 10)
		if not newline or newline >= position then break end
		scan, line = newline + 1, line + 1
	end
	return math.min(line, index.lineCount), true
end

function Document.getPositionForLine(self, line)
	if type(line) ~= "number" or line ~= math.floor(line) or line < 1 then
		return nil, "Line must be a positive whole number."
	end
	if not self:usesTextBuffer() then
		if line > #self then return nil, "Line is beyond the end of the document." end
		return line
	end
	local index = self:ensureDocumentIndex()
	if not index.lineCount or not index.lineOffsets or not index.lineIndexStride then
		return nil, "Exact line navigation is unavailable until the document index is refreshed."
	end
	if line > index.lineCount then return nil, "Line is beyond the end of the document." end
	local checkpoint
	if index.lineNumbers then
		local low, high = 1, #index.lineNumbers
		checkpoint = 1
		while low <= high do
			local middle = math.floor((low + high) / 2)
			if index.lineNumbers[middle] <= line then
				checkpoint, low = middle, middle + 1
			else high = middle - 1 end
		end
	else
		checkpoint = math.floor((line - 1) / index.lineIndexStride) + 1
	end
	local position = index.lineOffsets[checkpoint]
	local current = index.lineNumbers and index.lineNumbers[checkpoint] or
		((checkpoint - 1) * index.lineIndexStride + 1)
	while current < line do
		local newline = self._textbuffer:find(position, 10)
		if not newline then return nil, "Line is beyond the end of the document." end
		position, current = newline + 1, current + 1
	end
	return position
end

function Document.getPositionPercent(self, position)
	if self:usesTextBuffer() then
		local size = self._textbuffer:size()
		position = math.max(0, math.min(position or self._textpos, size))
		return size == 0 and 0 or math.floor(position * 100 / size)
	end
	if #self <= 1 then return 0 end
	local paragraph = math.max(1, math.min(position or self.cp, #self))
	return math.floor((paragraph - 1) * 100 / (#self - 1))
end

function Document.getPositionForPercent(self, percent)
	if type(percent) ~= "number" or percent < 0 or percent > 100 then
		return nil, "Percentage must be between 0 and 100."
	end
	if not self:usesTextBuffer() then
		if #self == 0 then return 1 end
		return math.floor((#self - 1) * percent / 100) + 1
	end
	local size = self._textbuffer:size()
	local position = math.floor(size * percent / 100)
	if position >= size then return size end
	while position > 0 do
		local byte = self._textbuffer:slice(position, 1):byte()
		if byte < 0x80 or byte >= 0xc0 then break end
		position = position - 1
	end
	-- Prefer a nearby logical-line boundary without turning a long line into
	-- an unbounded reverse scan.
	local nearby = self._textbuffer:rfind(math.max(0, position - 65536), 10, position)
	if nearby then position = nearby + 1 end
	return position
end

function Document.getPageCount(self)
	local index = EnsureDocumentPageIndex(self)
	return index and index.pageCount
end

function Document.getPageAtPosition(self, position)
	local index = EnsureDocumentPageIndex(self)
	if not index then return nil end
	return GetDocumentPageAtPosition(self, index, position)
end

function Document.getPositionForPage(self, page)
	if type(page) ~= "number" or page ~= math.floor(page) or page < 1 then
		return nil, "Page must be a positive whole number."
	end
	local index = EnsureDocumentPageIndex(self)
	if not index then return nil, "Page layout index is currently unavailable." end
	if page > index.pageCount then return nil, "Page is beyond the end of the document." end
	return GetDocumentPositionForPage(self, index, page)
end

function Document.gotoNavigationPosition(self, position, line)
	if self:usesTextBuffer() then
		self._textpos, self._texttop = position, position
		self._textline, self._texttopline = line, line
		Cmd.UnsetMark()
	else
		if type(position) == "table" then
			self.cp, self.cw, self.co = position.p, position.w, position.o
		else
			self.cp, self.cw, self.co = position, 1, 1
		end
	end
	QueueRedraw()
	return true
end

local function adjust_spans(spans, position, removed, added)
	local removed_end = position + removed
	local function translate(offset)
		if offset <= position then return offset end
		if offset >= removed_end then return offset - removed + added end
		return position + added
	end
	local output = {count=0}
	for _, span in ipairs(spans) do
		local start = translate(span.start)
		local finish = translate(span.finish)
		if finish > start then
			span.start, span.finish = start, finish
			output[#output+1] = span
		end
	end
	output.count = #output
	return output
end

function Document.adjustLargeStyleSpans(self, position, removed, added)
	local metadata = self:ensureDocumentIndex()
	local lineDelta, wordDelta, visibleDelta = self._textbuffer:changestats()
	if lineDelta and metadata.wordCount and metadata.lineCount and
			metadata.lineOffsets and metadata.lineIndexStride then
		metadata.wordCount = math.max(0, metadata.wordCount + wordDelta)
		metadata.lineCount = math.max(1, metadata.lineCount + lineDelta)
		metadata.lineNumbers = metadata.lineNumbers or {}
		if #metadata.lineNumbers == 0 then
			for i = 1, #metadata.lineOffsets do
				metadata.lineNumbers[i] = (i - 1) * metadata.lineIndexStride + 1
			end
		end
		local byteDelta = added - removed
		local oldEnd = position + removed
		for i = #metadata.lineOffsets, 1, -1 do
			local offset = metadata.lineOffsets[i]
			if removed > 0 and offset > position and offset < oldEnd then
				table.remove(metadata.lineOffsets, i)
				table.remove(metadata.lineNumbers, i)
			elseif (removed > 0 and offset >= oldEnd) or
					(removed == 0 and offset > position) then
				metadata.lineOffsets[i] = offset + byteDelta
				metadata.lineNumbers[i] = metadata.lineNumbers[i] + lineDelta
			end
		end
		-- Re-layout only the logical line(s) touched by an insertion. This makes
		-- Enter/newline typing update physical pages without rescanning the
		-- mapped document. Existing sparse page checkpoints merely translate.
		local page = self._pageIndex or metadata.pageLayoutIndex
		local inverse = self._pageEditInverse
		local inverseMatch = inverse and inverse.position == position and
			inverse.removed == removed and inverse.added == added
		local pageSafe = page and page.visualLineCount and
			(removed == 0 or inverseMatch)
		local visualRowDelta = 0
		if pageSafe and inverseMatch then
			visualRowDelta = inverse.visualRowDelta
			page.visualLineCount = page.visualLineCount + visualRowDelta
			page.pageCount = math.max(1, math.floor(
				(page.visualLineCount - 1) / page.rows) + 1)
		elseif pageSafe then
			local start = self:textLineBounds(position)
			local finish = self._textbuffer:find(position + added, 10) or
				self._textbuffer:size()
			if finish - start <= 16 * 1024 * 1024 then
				local newText = self._textbuffer:slice(start, finish - start)
				local relative = position - start
				local oldText = newText:sub(1, relative)..
					newText:sub(relative + added + 1)
				local function layoutRows(text)
					local rows, visible = 0, 0
					local function finishLine()
						rows = rows + math.max(1, math.floor(
							(visible + page.columns - 1) / page.columns))
						visible = 0
					end
					for i = 1, #text do
						local c = text:byte(i)
						if c == 10 then finishLine()
						elseif c >= 0x20 and c ~= 0x7f and
								(c < 0x80 or c >= 0xc0) then
							visible = visible + 1
						end
					end
					finishLine()
					return rows
				end
				visualRowDelta = layoutRows(newText) - layoutRows(oldText)
				local oldCheckpointCount = math.floor((page.pageCount - 1) /
					page.pageIndexStride) + 1
				local newVisualLines = page.visualLineCount + visualRowDelta
				local newPageCount = math.max(1, math.floor(
					(newVisualLines - 1) / page.rows) + 1)
				local newCheckpointCount = math.floor((newPageCount - 1) /
					page.pageIndexStride) + 1
				pageSafe = oldCheckpointCount == newCheckpointCount
				if pageSafe then
					page.visualLineCount = newVisualLines
					page.pageCount = newPageCount
				end
			else pageSafe = false end
		end
		if pageSafe then
			for i, offset in ipairs(page.pageOffsets) do
				if offset > position then page.pageOffsets[i] = offset + byteDelta end
			end
			metadata.pageLayoutIndex, self._pageIndex = page, page
			self._pageEditInverse = {position=position, removed=added,
				added=removed, visualRowDelta=-visualRowDelta}
		else
			metadata.pageLayoutIndex, self._pageIndex = nil, nil
			self._pageEditInverse = nil
		end
		-- Callers may move the cursor immediately after applying the edit. Do
		-- not cache its pre-move line; leave cursor lookup to the sparse index.
		-- The viewport itself has already reached its final position here.
		self._textline = nil
		self._texttopline = self:getLineAtPosition(self._texttop)
	else
		metadata.wordCount = nil
		metadata.lineCount = nil
		metadata.lineOffsets = nil
		metadata.lineNumbers = nil
		metadata.pageLayoutIndex = nil
		self._pageIndex = nil
		self._textline, self._texttopline = nil, nil
	end
	metadata.characterStyles = adjust_spans(metadata.characterStyles,
		position, removed, added)
	metadata.paragraphStyles = adjust_spans(metadata.paragraphStyles,
		position, removed, added)
end

function Document.addLargeCharacterStyle(self, start, finish, style)
	if finish <= start then return false end
	local spans = self:ensureDocumentIndex().characterStyles
	spans[#spans+1] = {start=start, finish=finish, style=style}
	spans.count = #spans
	return true
end

function Document.addLargeParagraphStyle(self, start, finish, style)
	if finish <= start then return false end
	local spans = self:ensureDocumentIndex().paragraphStyles
	spans[#spans+1] = {start=start, finish=finish, style=style}
	spans.count = #spans
	return true
end

function Document.largeCharacterStyleAt(self, position)
	local mask = 0
	local metadata = self:ensureDocumentIndex()
	for _, span in ipairs(metadata and metadata.characterStyles or {}) do
		if position >= span.start and position < span.finish then
			if span.style == 0 then mask = 0 else mask = bit32.bor(mask, span.style) end
		end
	end
	return mask
end

function Document.largeParagraphStyleAt(self, position)
	local style = "P"
	local metadata = self:ensureDocumentIndex()
	for _, span in ipairs(metadata and metadata.paragraphStyles or {}) do
		if position >= span.start and position < span.finish then style = span.style end
	end
	return style
end

function Document.deleteTextRange(self, start, length)
	local undoable = self._textbuffer:delete(start, length)
	self:adjustLargeStyleSpans(start, length, 0)
	if undoable == false then
		-- Deliver after the command finishes, so follow-up messages such as
		-- "Selected text deleted" cannot replace this safety warning.
		FireAsyncEvent("LargeTextUndoHistoryCleared")
	end
	return undoable
end

AddEventListener("LargeTextUndoHistoryCleared", function()
	NonmodalMessage("Large deletion completed; undo history was cleared.")
	QueueRedraw()
end)

function CreateTextBufferDocument(filename, content_offset, content_length)
	local buffer, e = wg.opentextbuffer(filename, content_offset, content_length)
	if not buffer then return nil, e end
	local document = CreateDocument()
	document._textbuffer = buffer
	document._textsource = filename
	document._textpos = 0
	document._texttop = 0
	document._textline = 1
	document._texttopline = 1
	document._textchanged = false
	return document
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
	local paragraphabove = self[pn - 1]

	-- Space above exists to separate a paragraph from whatever precedes it.
	-- With nothing above the very first paragraph, there's nothing to
	-- separate from, so no space is owed here -- otherwise it shows up as a
	-- phantom blank row wherever the document start has a fixed reference
	-- point to reveal it against, e.g. the ruler drawn above the document
	-- when terminators are on.
	if not paragraphabove then
		return 0
	end

	local paragraph = self[pn]
	local sa = documentStyles[paragraph.style].above or 0 -- FIXME
	local sb = documentStyles[paragraphabove.style].below or 0 -- FIXME

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
	if self:usesTextBuffer() then
		return
	end
	local wc = 0
	local pn = 1

	for _, p in ipairs(self) do
		for _, word in ipairs(p) do
			if GetWordText(word):find("%S") then wc = wc + 1 end
		end

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
	local viewmode = GetDefaultMarginMode()
	local d =
	{
		_wrapwidth = 0,
		viewmode = viewmode,
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
	dd.margin = GetMarginWidthForMode(viewmode, dd)
	return dd
end
