--!nonstrict
-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local Write = wg.write
local GotoXY = wg.gotoxy
local ClearScreen = wg.clearscreen
local ClearArea = wg.cleararea
local SetNormal = wg.setnormal
local SetBold = wg.setbold
local SetBright = wg.setbright
local SetUnderline = wg.setunderline
local SetItalic = wg.setitalic
local SetReverse = wg.setreverse
local SetDim = wg.setdim
local GetStringWidth = wg.getstringwidth
local ShowCursor = wg.showcursor
local HideCursor = wg.hidecursor
local Sync = wg.sync

local UseUnicode = wg.useunicode
local BLINK_TIME = 0.8

local function setLargeTextStyle(mask, selected)
	SetNormal()
	if bit32.btest(mask, wg.BOLD) then SetBold() end
	if bit32.btest(mask, wg.ITALIC) then SetItalic() end
	if bit32.btest(mask, wg.UNDERLINE) then SetUnderline() end
	if bit32.btest(mask, wg.BRIGHT) then SetBright() end
	if selected then SetReverse() end
end

function BuildLargeTextStyleRuns(document, first, finish, selection_start,
		selection_end, paragraph_style)
	local boundaries = {first, finish}
	local metadata = document:ensureDocumentIndex()
	for _, span in ipairs(metadata and metadata.characterStyles or {}) do
		if span.start < finish and span.finish > first then
			boundaries[#boundaries+1] = math.max(first, span.start)
			boundaries[#boundaries+1] = math.min(finish, span.finish)
		end
	end
	if selection_start and selection_end then
		if selection_start > first and selection_start < finish then
			boundaries[#boundaries+1] = selection_start
		end
		if selection_end > first and selection_end < finish then
			boundaries[#boundaries+1] = selection_end
		end
	end
	table.sort(boundaries)
	local previous, runs = nil, {}
	for _, start in ipairs(boundaries) do
		if previous and start > previous then
			local mask = bit32.bor(GetParagraphStyleMarkup(paragraph_style),
				document:largeCharacterStyleAt(previous))
			local selected = selection_start and selection_end and
				previous >= selection_start and previous < selection_end
			runs[#runs+1] = {first=previous, finish=start, mask=mask,
				selected=not not selected}
		end
		previous = start
	end
	return runs
end

local function drawLargeTextRange(document, x, y, first, finish,
		selection_start, selection_end, paragraph_style)
	for _, run in ipairs(BuildLargeTextStyleRuns(document, first, finish,
			selection_start, selection_end, paragraph_style)) do
		setLargeTextStyle(run.mask, run.selected)
		Write(x + document:textCellOffset(first, run.first), y,
			document._textbuffer:slice(run.first, run.finish - run.first))
	end
	SetNormal()
end

local messages = {}
local lineindex = {}
local papermargin = 0
local paperwidth = 0
local usablewidth = 0

-- The rightmost column of the screen is permanently reserved for the
-- vertical scrollbar (see drawscrollbar() below); no document/paper/margin
-- content is ever drawn there. One extra blank column is kept free just to
-- its left as a fixed gutter, so the ruler/paper edge is never immediately
-- adjacent to the scrollbar.
local SCROLLBAR_WIDTH = 1
local SCROLLBAR_GUTTER = 1

local SCROLLBAR_SYMBOLS = {
	up    = { "↑", "^" },
	down  = { "↓", "v" },
	track = { "│", "|" },
	thumb = { "█", "#" },
}

local SYMBOLS = {
	[0] = { "₀", "0" },
	[1] = { "₁", "1" },
	[2] = { "₂", "2" },
	[3] = { "₃", "3" },
	[4] = { "₄", "4" },
	[5] = { "₅", "5" },
	[6] = { "₆", "6" },
	[7] = { "₇", "7" },
	[8] = { "₈", "8" },
	[9] = { "₉", "9" },
	dl =  { "◥", "\\" },
	dm =  { "▼", "+" },
	dms = { "▾", "." },
	tab = { "T", "T" },
	dr =  { "◤", "/" },
	ul =  { "◿", "/" },
	um =  { "△", "+" },
	ur =  { "◺", "\\" },
	lb =  { "▁", "-" },
	lt =  { "▔", "-" },
}

function NonmodalMessage(s)
	messages[#messages+1] = s
	QueueRedraw()
end

function ResetNonmodalMessages()
	messages = {}
end

function ResizeScreen()
	ScreenWidth, ScreenHeight = wg.getscreensize()
	usablewidth = math.max(ScreenWidth - SCROLLBAR_WIDTH - SCROLLBAR_GUTTER, 0)
	local w = GetMaximumAllowedWidth(usablewidth)
	if GetEditorWidthMode() == "Page preview" then
		w = math.min(w, GetDocumentTextWidthColumns(currentDocument))
	end
	if currentDocument.margin > 0 then
		-- Margin annotations (e.g. paragraph numbers) need at least this
		-- much space on the left. When nothing else constrains the paper
		-- width (no widescreen cap), fill the rest of the line with it
		-- instead of mirroring an empty gutter on the right -- that space
		-- belongs to the scrollbar, not the margin. But if a widescreen
		-- maximum-width cap actually leaves room to spare, still center
		-- the (narrower) paper within it, same as with no margin active.
		local mingutter = currentDocument.margin + 2
		paperwidth = math.max(1, math.min(w, usablewidth - mingutter))

		-- Same centering in both scroll modes: when nothing narrower than
		-- the screen constrains the paper, paperwidth already fills
		-- usablewidth - mingutter, so this comes out to mingutter itself --
		-- pinning the gutter to its minimum and filling the rest of the row
		-- with paper, rather than a wide unused strip mirrored on the left.
		-- It's only once a width cap (Column limit / Page preview) actually
		-- leaves room to spare that this centers the (narrower) paper
		-- within it, same as with no margin active.
		local centeredmargin = math.floor((usablewidth - paperwidth) / 2)
		papermargin = math.max(mingutter, centeredmargin)

		-- Keep the blank strip on the right small -- about as wide as the
		-- scrollbar column itself -- instead of mirroring the (often much
		-- wider) left gutter the annotation needs. Give any width that
		-- frees up to the paper rather than leaving it empty.
		local rightgutter = SCROLLBAR_WIDTH + SCROLLBAR_GUTTER
		paperwidth = math.min(w,
			math.max(paperwidth, usablewidth - papermargin - rightgutter))
	else
		papermargin = math.floor(usablewidth/2 - w/2)
		paperwidth = usablewidth - papermargin*2
	end
	currentDocument:wrap(paperwidth)
	return true
end

-- papermargin/paperwidth stay private module state (unlike ScreenWidth/
-- ScreenHeight, which are plain globals) since nothing outside this file's
-- drawing code should mutate them mid-frame. This is the read-only way in.
function GetPaperLayout()
	return papermargin, paperwidth
end

local function drawmargin(y, pn, p)
	local controller = marginControllers[currentDocument.viewmode]
	if controller.getcontent then
		local s= assert(controller.getcontent)(controller, pn, p)

		if s then
			SetColour(Palette.StyleFG, Palette.Desktop)
			SetDim()
			RAlignInField(0, y, papermargin - 1, s)
		end
	end

	local style = documentStyles[p.style]
	local function drawbullet(n)
		local w = GetStringWidth(n) + 1
		local i = (style.indent or 0)
		if (i >= w) then
			SetNormal()
			SetColour(Palette.LB_FG, Palette.LB_BG)
			Write(papermargin + i - w, y, n)
		end
	end

	local bullet = style.bullet
	if bullet then
		drawbullet(bullet)
	else
		local numbered = style.numbered
		if numbered then
			local n = tostring(p.number or 0).."."
			drawbullet(n)
		end
	end
end

local changed_tab =
{
	[true] = "CHANGED"
}

local function redrawstatus()
	local y = ScreenHeight - 1

	if documentSet.statusbar then
		local s = {
			Leafname(documentSet.name or "(unnamed)"),
			"[",
			currentDocument.name or "",
			"] ",
			changed_tab[documentSet._changed] or "",
		}

		-- Reversed due to SetReverse later.
		SetColour(Palette.StatusbarBG, Palette.StatusbarFG)
		SetReverse()
		ClearArea(0, ScreenHeight-1, ScreenWidth-1, ScreenHeight-1)
		LAlignInField(0, ScreenHeight-1, ScreenWidth, table.concat(s, ""))

		local ss= {}
		FireEvent("BuildStatusBar", ss)
		table.sort(ss, function(x, y) return x.priority < y.priority end)

		-- Keep the established term order and priorities. On constrained
		-- terminals first use each addon's compact spelling, then omit the
		-- lowest-priority optional terms until the right side cannot overwrite
		-- the document identity on the left.
		local leftwidth = GetStringWidth(table.concat(s, ""))
		local available = math.max(0, ScreenWidth - math.min(leftwidth + 1,
			math.max(16, math.floor(ScreenWidth / 3))))
		local function termswidth()
			local width = 0
			for _, term in ipairs(ss) do
				if not term.hidden then
					if width > 0 then width = width + 3 end
					width = width + GetStringWidth(term.displayvalue or term.value)
				end
			end
			return width
		end
		if termswidth() > available then
			for _, term in ipairs(ss) do term.displayvalue = term.shortvalue or term.value end
		end
		if termswidth() > available then
			for _, term in ipairs(ss) do
				if not term.mandatory then
					term.hidden = true
					if termswidth() <= available then break end
				end
			end
		end

		local s = {" "}
		for _, v in ipairs(ss) do
			if not v.hidden then s[#s+1] = v.displayvalue or v.value end
		end
		local ss = table.concat(s, " │ ")
		if (string.sub(ss, #ss) == " ") then
			ss = string.sub(ss, 1, #ss-1)
		end

		RAlignInField(0, ScreenHeight-1, ScreenWidth, ss)
		SetNormal()

		y = y - 1
	end

	if (#messages > 0) then
		-- Reversed due to SetReverse later.
		SetColour(Palette.MessageFG, Palette.MessageBG)
		SetReverse()

		for i = #messages, 1, -1 do
			ClearArea(0, y, ScreenWidth-1, y)
			Write(0, y, messages[i])
			y = y - 1
		end

		SetNormal()
	end
end

local function drawtopmarker(y)
	local lm = papermargin
	local rm = lm + paperwidth - 1
	local w = rm - lm + 1
	local u = UseUnicode() and 1 or 2

	SetNormal()
	SetColour(Palette.MarkerFG, Palette.Desktop)
	if y >= 2 then
		-- Each tick is 10 columns apart and labelled with how many tens of
		-- columns it is from the margin (0, 1, 2, ..., 9, 10, 11, ...) --
		-- this must keep counting past 9 rather than wrapping back to a
		-- single digit, or ticks past column 100 would be ambiguous.
		local n = 0
		for i = lm, rm, 10 do
			local digits = tostring(n)
			local label = {}
			for d = 1, #digits do
				label[d] = SYMBOLS[tonumber(digits:sub(d, d))][u]
			end
			-- Keep the label as one unbroken run (splitting it around the
			-- tick column reads as two separate numbers instead of one),
			-- nudged left by half its digit count so it settles roughly on
			-- the tick (column `i`, where the ▼ mark is drawn one row
			-- below) instead of always starting there -- the more digits
			-- get added, the further left it shifts.
			local shift = #digits // 2
			Write(math.max(lm, i - shift), y-2, table.concat(label))
			n = n + 1
		end
	end
	if y >= 1 then
		Write(lm, y-1, SYMBOLS.dl[u])
		for i = lm+5, rm, 10 do
			Write(i, y-1, SYMBOLS.dms[u])
		end
		for i = lm+10, rm, 10 do
			Write(i, y-1, SYMBOLS.dm[u])
		end
		-- Only show tabs actually present on the cursor's visual line. Each
		-- inserted tab carries an invisible marker, so ordinary runs of spaces
		-- are deliberately ignored.
		local paragraph = currentDocument[currentDocument.cp]
		if paragraph then
			local wd = paragraph:wrap()
			local ln = paragraph:getLineOfWord(
				currentDocument.cw, currentDocument.co)
			local line = wd.lines[ln]
			if line and not line.fragment and not line.leadingfragment then
				for _, wn in ipairs(line) do
					if WordHasTabMarker(paragraph[wn]) then
						local stop = lm + (wd.xs[wn] or 0) +
							GetStringWidth(paragraph[wn]) + 1
						if stop > lm and stop < rm then
							Write(stop, y-1, SYMBOLS.tab[u])
						end
					end
				end
			end
		end
		Write(rm, y-1, SYMBOLS.dr[u])
	end

	SetColour(Palette.MarkerFG, Palette.Paper)
	ClearArea(lm, y, rm, y)
	for i = lm+1, rm-1 do
		Write(i, y, SYMBOLS.lt[u])
	end
end

local function drawbottommarker(y)
	local lm = papermargin
	local rm = lm + paperwidth - 1
	local w = rm - lm + 1
	local u = UseUnicode() and 1 or 2
	local status_y = documentSet.statusbar and (ScreenHeight - 1) or ScreenHeight

	if y < status_y then
		SetNormal()
		SetColour(Palette.MarkerFG, Palette.Paper)
		ClearArea(lm, y, rm, y)
		for i = lm+1, rm-1 do
			Write(i, y, SYMBOLS.lb[u])
		end
	end
	y = y + 1
	if y < status_y then
		SetNormal()
		SetColour(Palette.MarkerFG, Palette.Desktop)
		ClearArea(lm, y, rm, y)
		Write(lm, y, SYMBOLS.ul[u])
		for i = lm+10, rm, 10 do
			Write(i, y, SYMBOLS.um[u])
		end
		Write(rm, y, SYMBOLS.ur[u])
	end
end

-- Fixed mode's cursor row used to be recomputed from the document start on
-- every redraw, which pins it to the bottom row as soon as the document is
-- longer than one screenful (see the "cy" clamp below) -- so moving the
-- cursor to *any* other paragraph, even one already fully visible (e.g. a
-- mouse click a few lines above where you'd been typing), yanked that
-- whole page up to make the clicked line the new bottom row. This works
-- out whether (cp, cw) is already visible within `height` rows of the
-- previous frame's top-left anchor (topp, topw) and, if so, returns which
-- row it's on -- so the caller can keep that same viewport instead of
-- rescrolling. Returns nil if it isn't visible (or there's no prior
-- frame yet), in which case the caller falls back to the old behaviour.
local function rowoffsetfromtop(topp, topw, cp, cw, co, height)
	if not topp or (cp < topp) then
		return nil
	end

	local topparagraph = currentDocument[topp]
	if not topparagraph then
		return nil
	end
	-- Viewport anchors describe the previous frame. Editing can delete or
	-- merge the paragraph/word they point at (select-all + Backspace is the
	-- simplest case), so an invalid anchor means "recompute the viewport",
	-- not a fatal document error.
	local ok, topline = pcall(topparagraph.getLineOfWord,
		topparagraph, topw)
	if not ok then
		return nil
	end
	if not topline then
		return nil
	end

	local row
	if cp == topp then
		local cursorok, cline = pcall(topparagraph.getLineOfWord,
			topparagraph, cw, co)
		if not cursorok then
			return nil
		end
		if not cline or (cline < topline) then
			return nil
		end
		row = (cline - topline) *
			GetDocumentLineHeightRows(currentDocument, topparagraph.style)
	else
		row = ((#topparagraph:wrap().lines - topline) + 1) *
			GetDocumentLineHeightRows(currentDocument, topparagraph.style) +
			currentDocument:spaceBelow(topp)

		for p = topp + 1, cp - 1 do
			local paragraph = currentDocument[p]
			if not paragraph then
				return nil
			end
			row = row + #paragraph:wrap().lines *
				GetDocumentLineHeightRows(currentDocument, paragraph.style) +
				currentDocument:spaceBelow(p)
			if row >= height then
				return nil
			end
		end

		local cparagraph = currentDocument[cp]
		if not cparagraph then
			return nil
		end
		local cursorok, cline = pcall(cparagraph.getLineOfWord,
			cparagraph, cw, co)
		if not cursorok then
			return nil
		end
		if not cline then
			return nil
		end
		row = row + (cline - 1) *
			GetDocumentLineHeightRows(currentDocument, cparagraph.style)
	end

	if (row < 0) or (row >= height) then
		return nil
	end
	return row
end

-- Works out how many screen rows the whole document occupies, and which of
-- those rows the topmost currently-drawn paragraph+word
-- (currentDocument._topp/_topw, set by the fixed/jump drawing passes
-- above) corresponds to. Used only to feed the scrollbar geometry
-- calculation -- purely visual, never touches document state.
--
-- This has to mirror row-for-row what the drawing passes below actually
-- put on screen, or the scrollbar thumb drifts out of proportion to what's
-- visible. Two things after a paragraph's own text lines eat real rows
-- there: its line-height multiplier (GetDocumentLineHeightRows -- more
-- than 1 row per wrapped line under non-default line spacing) and the
-- blank spacer rows between paragraphs (spaceAbove/spaceBelow, e.g. extra
-- space around headings). Leaving either out means paragraphs with more
-- of that spacing get undercounted relative to how many rows they
-- actually take, which drifts the document total and the thumb's
-- position in it.
local function computelinerange()
	local total = 0
	local topline
	local count = #currentDocument

	for pn = 1, count do
		local paragraph = currentDocument[pn]
		local lineheight = GetDocumentLineHeightRows(currentDocument, paragraph.style)
		local nlines = #paragraph:wrap().lines

		if pn == currentDocument._topp then
			local line = paragraph:getLineOfWord(currentDocument._topw) or 1
			topline = total + (line - 1) * lineheight + 1
		end

		total = total + nlines * lineheight
		if pn < count then
			total = total + currentDocument:spaceBelow(pn)
		end
	end

	return total, topline
end

-- top_y/bottom_y are the first/last screen row the scrollbar may use --
-- i.e. the rows that actually track the document text, excluding any
-- rows permanently reserved for a fixed-mode ruler.
local function drawscrollbar(top_y, bottom_y)
	local height = bottom_y - top_y + 1
	if height < 2 then
		return
	end

	local x = ScreenWidth - SCROLLBAR_WIDTH
	local total, topline = computelinerange()

	-- How many rows are actually filled with document text this frame is
	-- read straight from the rows the drawing passes above recorded
	-- (_topy/_boty) instead of being reconstructed from paragraph/word
	-- positions here: a reconstruction can drift by a row or two right at
	-- a paragraph transition with unusual spacing (e.g. a heading), which
	-- is exactly what made the thumb visibly resize while scrolling even
	-- once the `total`/`topline` accounting above already matched the
	-- drawing passes.
	local visible = 1
	if currentDocument._topy and currentDocument._boty and
			(currentDocument._boty >= currentDocument._topy) then
		visible = currentDocument._boty - currentDocument._topy + 1
	end

	local geom = ComputeScrollbarGeometry(total, topline or 1, visible, height)
	local u = UseUnicode() and 1 or 2

	SetNormal()
	SetColour(Palette.MarkerFG, Palette.Desktop)
	Write(x, top_y, SCROLLBAR_SYMBOLS.up[u])
	Write(x, bottom_y, SCROLLBAR_SYMBOLS.down[u])

	if geom.track_height > 0 then
		SetColour(Palette.StyleFG, Palette.Desktop)
		SetDim()
		for row = 0, geom.track_height - 1 do
			Write(x, top_y + 1 + row, SCROLLBAR_SYMBOLS.track[u])
		end

		SetNormal()
		SetColour(Palette.ScrollbarFG, Palette.ScrollbarBG)
		for row = geom.thumb_start, geom.thumb_start + geom.thumb_size - 1 do
			Write(x, top_y + 1 + row, SCROLLBAR_SYMBOLS.thumb[u])
		end
	end

	SetNormal()
end

local function drawtextscrollbar(top_y, bottom_y, first, last, total)
	local height = bottom_y - top_y + 1
	if height < 2 then return end
	local x = ScreenWidth - SCROLLBAR_WIDTH
	local visible = math.max(1, last - first)
	local geom = ComputeScrollbarGeometry(math.max(1, total), first + 1,
		visible, height)
	local u = UseUnicode() and 1 or 2
	SetNormal()
	SetColour(Palette.MarkerFG, Palette.Desktop)
	Write(x, top_y, SCROLLBAR_SYMBOLS.up[u])
	Write(x, bottom_y, SCROLLBAR_SYMBOLS.down[u])
	if geom.track_height > 0 then
		SetColour(Palette.StyleFG, Palette.Desktop)
		SetDim()
		for row = 0, geom.track_height - 1 do
			Write(x, top_y + 1 + row, SCROLLBAR_SYMBOLS.track[u])
		end
		SetNormal()
		SetColour(Palette.ScrollbarFG, Palette.ScrollbarBG)
		for row = geom.thumb_start, geom.thumb_start + geom.thumb_size - 1 do
			Write(x, top_y + 1 + row, SCROLLBAR_SYMBOLS.thumb[u])
		end
	end
	SetNormal()
end

-- Piece tables are a storage backend, not a second UI. This renderer only
-- supplies visible text rows; all surrounding chrome is shared with the
-- regular WordProcess frontend (paper, rulers, margins, status and scrollbar).
local function redrawtextbuffer()
	SetColour(nil, Palette.Desktop)
	ClearScreen()
	local document = currentDocument
	if document.viewmode == 3 then
		local line = document:getLineAtPosition()
		local marginwidth = #tostring(line or 1)
		if document.margin ~= marginwidth then
			document.margin = marginwidth
			ResizeScreen()
		end
	end
	if document._textbuffer:sourcechanged() then
		redrawstatus()
		DrawStatusLine("Source file changed on disk; close and import it again safely.")
		GotoXY(0, 0)
		return
	end

	local fixed = GetScrollMode() == "Fixed"
	local terminators = WantTerminators() and ScreenHeight >= 8
	local status_y = documentSet.statusbar and (ScreenHeight - 1) or ScreenHeight
	local lm, rm = papermargin, papermargin + paperwidth - 1
	local min_y, max_y = 0, status_y - 1
	local top_marker, bottom_marker
	if fixed and terminators then
		min_y, max_y = 3, status_y - 3
		top_marker, bottom_marker = 2, status_y - 2
	elseif terminators and (document._texttop or 0) == 0 then
		min_y, top_marker = 3, 2
	end

	-- Navigation commands (arrows, Goto, search, page up/down) keep _texttop
	-- in sync with the cursor as they move it. Edits that move the cursor
	-- instead -- Backspace/Delete joining lines, typing a newline, pasting,
	-- undo/redo -- don't, so without this the viewport can silently stop
	-- containing the cursor: the screen keeps showing whatever it last
	-- scrolled to while the cursor (and the edits happening at it) drift off
	-- the top or bottom, invisible.
	document:ensureTextCursorVisible(max_y - min_y + 1)

	SetColour(Palette.P_FG, Palette.P_BG)
	SetNormal()
	ClearArea(lm, min_y, rm, max_y)
	lineindex = {}

	local line_start = document:textLineBounds()
	local offset = document._texttop or line_start
	local selection_start, selection_end = document:textSelection()
	local cursor_column = document:textCellOffset(line_start, document._textpos)
	local horizontal = document._texthorizontal or 0
	if cursor_column < horizontal then horizontal = cursor_column end
	if cursor_column >= horizontal + paperwidth then
		horizontal = cursor_column - paperwidth + 1
	end
	document._texthorizontal = horizontal
	local cursor_y = min_y
	local cursor_display_start = line_start
	local y = min_y
	local visible_line = document._texttopline

	local buffersize = document._textbuffer:size()
	-- A trailing newline creates one real, empty line at EOF. Draw that line
	-- when it contains the cursor; otherwise cursor_y remains at min_y and the
	-- visible cursor incorrectly jumps to the top of the window.
	while y <= max_y and (offset < buffersize or
			(offset == buffersize and document._textpos == buffersize)) do
		if offset == line_start then cursor_y = y end
		local newline = document._textbuffer:find(offset, 10)
		local finish = newline or buffersize
		if finish > offset and document._textbuffer:slice(finish - 1, 1) == "\r" then
			finish = finish - 1
		end
		local display_start, visible_end = document:textViewport(offset, finish,
			horizontal, paperwidth)
		if offset == line_start then cursor_display_start = display_start end
		local length = visible_end - display_start
		local paragraph_style = document:largeParagraphStyleAt(offset)
		SetColour(Palette.P_FG, Palette.P_BG)
		SetNormal()
		if length > 0 then
			drawLargeTextRange(document, lm, y, display_start, visible_end,
				selection_start, selection_end, paragraph_style)
		end

		if currentDocument.viewmode > 1 and papermargin > 1 then
			local label
			if currentDocument.viewmode == 2 then label = paragraph_style
			elseif currentDocument.viewmode == 3 then
				label = visible_line and tostring(visible_line) or "~"
			elseif currentDocument.viewmode == 4 then
				local shown = length > 0 and
					document._textbuffer:slice(display_start, length) or ""
				local count = 0
				for _ in shown:gmatch("%S+") do count = count + 1 end
				label = tostring(count)
			end
			if label then
				SetColour(Palette.StyleFG, Palette.Desktop)
				SetDim()
				RAlignInField(0, y, papermargin - 1, label)
			end
		end

		lineindex[y + 1] = {textoffset = offset, textdisplaystart = display_start}
		if not newline then
			offset = buffersize
			break
		end
		offset = newline + 1
		if visible_line then visible_line = visible_line + 1 end
		y = y + 1
	end
	document._textbottom = offset

	if top_marker then drawtopmarker(top_marker) end
	if fixed and bottom_marker then
		drawbottommarker(bottom_marker)
	elseif terminators and offset >= document._textbuffer:size() and y <= max_y then
		drawbottommarker(y)
	end
	-- Measure the viewport in real (newline-delimited) lines rather than
	-- bytes. Each screen row here always holds exactly one such line, but
	-- how many *bytes* that line takes varies with its content (a heading
	-- or blank line spans far fewer bytes than a full paragraph line), so
	-- a byte-based "visible" span shrinks and grows with local content
	-- density even though the same number of rows is always drawn. Line
	-- counts don't have that problem: they track rows 1:1.
	local topline = (document:getLineAtPosition(document._texttop or 0) or 1) - 1
	local bottomline = (document:getLineAtPosition(offset) or (topline + 1)) - 1
	local linecount = document:getLineCount() or (bottomline + 1)
	drawtextscrollbar(0, status_y - 1, topline, bottomline, linecount)
	redrawstatus()
	GotoXY(lm + math.min(document:textCellOffset(cursor_display_start,
		document._textpos),
		paperwidth - 1), cursor_y)
	FireEvent("Redraw")
end

function RedrawScreen()
	-- We can't actual draw until the first resize event has been processed.
	if ScreenHeight == 0 then
		return
	end
	if currentDocument:usesTextBuffer() then
		return redrawtextbuffer()
	end

	SetColour(nil, Palette.Desktop)
	ClearScreen()

	local is_fixed_mode = (GetScrollMode() == "Fixed")
	local has_terminators = WantTerminators() and (ScreenHeight >= 8)
	local status_y = documentSet.statusbar and (ScreenHeight - 1) or ScreenHeight

	local lm = papermargin
	local rm = lm + paperwidth - 1
	-- Column 0 of the top/bottom ruler's tick marks (drawn at `papermargin`
	-- in drawtopmarker/drawbottommarker) must line up with column 0 of the
	-- actual text -- otherwise the cursor starts drawing one column to the
	-- right of where the ruler shows "0".
	local tx = papermargin

	-- The scrollbar always tracks the whole viewport height, from the
	-- first row to the last row above the status bar. It's kept clear of
	-- the ruler by column separation (SCROLLBAR_GUTTER, see ResizeScreen)
	-- rather than by shrinking its height.
	local scrollbar_top, scrollbar_bottom = 0, status_y - 1

	local mp = currentDocument.mp
	local mw = currentDocument.mw
	local mo = currentDocument.mo

	local function setparacolour(paragraph)
		SetColour(
			Palette[paragraph.style.."_FG"] or Palette.P_FG,
			Palette[paragraph.style.."_BG"] or Palette.P_BG)
	end

	lineindex = {}

	if is_fixed_mode then
		-- ====================================================================
		-- FIXED MODE: Top and bottom rulers are pinned to window edges,
		-- paper occupies the full height, document starts at the top.
		-- ====================================================================
		local min_y = has_terminators and 3 or 0
		local bot_marker_y = has_terminators and (status_y - 2) or nil
		local max_y = has_terminators and (status_y - 3) or (status_y - 1)

		if has_terminators and bot_marker_y and (bot_marker_y >= min_y) then
			SetColour(Palette.Paper, Palette.Paper)
			SetNormal()
			ClearArea(lm, min_y, rm, bot_marker_y)
		end

		local cp, cw, co = currentDocument.cp, currentDocument.cw, currentDocument.co
		currentDocument._sp = cp
		currentDocument._sw = cw

		-- If (cp, cw) was already visible in the viewport the *previous*
		-- frame drew, keep that same viewport rather than rescrolling --
		-- otherwise moving the cursor to any already-on-screen line (e.g.
		-- a mouse click) would yank the whole page to make that line the
		-- new bottom row (see rowoffsetfromtop's comment above).
		local row = rowoffsetfromtop(
			currentDocument._topp, currentDocument._topw,
			cp, cw, co, max_y - min_y + 1)

		local cy
		if row then
			cy = min_y + row
		else
			local lines_before = 0
			for p = 1, cp - 1 do
				local wd = currentDocument[p]:wrap()
				lines_before = lines_before + #wd.lines *
					GetDocumentLineHeightRows(currentDocument,
						currentDocument[p].style) + currentDocument:spaceBelow(p)
			end
			lines_before = lines_before +
				(currentDocument[cp]:getLineOfWord(cw, co) - 1) *
				GetDocumentLineHeightRows(currentDocument,
					currentDocument[cp].style)

			if (min_y + lines_before) <= max_y then
				cy = min_y + lines_before
			else
				cy = max_y
			end
		end

		-- Position cursor
		do
			local paragraph = currentDocument[cp]
			local wd = paragraph:wrap()
			local word = paragraph[cw]
			local cl = paragraph:getLineOfWord(cw, currentDocument.co)
			local wordx = paragraph:getXOffsetOfWord(cw, currentDocument.co)
			GotoXY(tx + wordx +
				GetWidthFromOffset(word, currentDocument.co) +
				paragraph:getIndentOfLine(cl),
				cy)
		end

		local function clear_fixed(y1, y2)
			y1 = math.max(min_y, y1)
			y2 = math.min(max_y, y2)
			if y1 <= y2 then
				SetNormal()
				ClearArea(lm, y1, rm, y2)
			end
		end

		local function drawline_fixed(paragraph, line, ln, y_pos, p_num)
			if (y_pos < min_y) or (y_pos > max_y) then
				return
			end
			local x = paragraph:getIndentOfLine(ln)

			setparacolour(paragraph)
			clear_fixed(y_pos, y_pos)
			if not mp then
				paragraph:renderLine(line, tx + x, y_pos)
			else
				paragraph:renderMarkedLine(line, tx + x, y_pos, nil, p_num)
			end

			if (ln == 1) then
				drawmargin(y_pos, p_num, paragraph)
			end

			lineindex[y_pos] = {
				p = p_num,
				w = paragraph:getWordOfLine(ln),
				x = tx
			}
		end

		local cl_cp = currentDocument[cp]:getLineOfWord(cw, co)
		local current_lineheight = GetDocumentLineHeightRows(currentDocument,
			currentDocument[cp].style)
		local y_cp = cy - (cl_cp - 1) * current_lineheight

		-- Draw backwards from cp - 1
		local y = y_cp - 1 - currentDocument:spaceAbove(cp)
		local pn = cp - 1
		currentDocument._topp = nil
		currentDocument._topw = nil
		currentDocument._topy = nil

		while (y >= min_y) and (pn >= 1) do
			local paragraph = currentDocument[pn]
			if not paragraph then
				break
			end

			local wd = paragraph:wrap()
			local lineheight = GetDocumentLineHeightRows(currentDocument,
				paragraph.style)
			for ln = #wd.lines, 1, -1 do
				local l = wd.lines[ln]
				drawline_fixed(paragraph, l, ln, y, pn)

				if (y >= min_y) and (y <= max_y) then
					currentDocument._topp = pn
					currentDocument._topw = l.wn
					currentDocument._topy = y
				end
				y = y - lineheight
				if y < min_y then
					break
				end
			end

			local sa = currentDocument:spaceAbove(pn)
			y = y - sa
			pn = pn - 1
		end

		-- pn >= 1 here means the loop stopped because a line or a spacing
		-- gap (e.g. the blank rows above a heading) pushed past the top of
		-- the viewport, not because the document ran out above -- so the
		-- viewport is fully packed edge-to-edge from here, blank spacer
		-- rows included. Its real top row is min_y even when the last
		-- actual text line landed a row or two below it: recording that
		-- lower row instead undercounts how many rows are genuinely on
		-- screen, which is what let the scrollbar thumb visibly resize
		-- while scrolling past paragraphs with different spacing.
		if pn >= 1 then
			currentDocument._topy = min_y
		end

		-- Draw forwards from cp
		y = y_cp
		pn = cp
		currentDocument._boty = nil
		while (y <= max_y) and (pn <= #currentDocument) do
			local paragraph = currentDocument[pn]
			if not paragraph then
				break
			end

			local wd = paragraph:wrap()
			local lineheight = GetDocumentLineHeightRows(currentDocument,
				paragraph.style)
			for ln, l in ipairs(wd.lines) do
				drawline_fixed(paragraph, l, ln, y, pn)

				if (y >= min_y) and (y <= max_y) then
					if not currentDocument._topp or (y == min_y) then
						currentDocument._topp = pn
						currentDocument._topw = l.wn
						currentDocument._topy = y
					end
					currentDocument._botp = pn
					currentDocument._botw = l.wn
					currentDocument._boty = y
				end
				y = y + lineheight
				if y > max_y then
					break
				end
			end
			local sb = currentDocument:spaceBelow(pn)
			y = y + sb
			pn = pn + 1
		end

		-- Symmetric with the backward pass above: pn still being a real
		-- paragraph means a line or spacing gap pushed past the bottom of
		-- the viewport rather than the document running out below, so the
		-- viewport's real bottom row is max_y regardless of where the last
		-- actual text line landed.
		if pn <= #currentDocument then
			currentDocument._boty = max_y
		end

		if not currentDocument._topp then
			currentDocument._topp = 1
			currentDocument._topw = 1
			currentDocument._topy = min_y
		end
		if not currentDocument._boty then
			currentDocument._boty = currentDocument._topy
		end

		if has_terminators and bot_marker_y then
			drawtopmarker(2)
			drawbottommarker(bot_marker_y)
		end
	else
		-- ====================================================================
		-- JUMP MODE: Classic typewriter mode where the document is centered
		-- and terminators float with the document start/end.
		-- ====================================================================
		if not currentDocument._sp then
			currentDocument._sp = currentDocument.cp
			currentDocument._sw = currentDocument.cw
		end
		local sp, sw = assert(currentDocument._sp), assert(currentDocument._sw)
		local cp, cw, co = currentDocument.cp, currentDocument.cw, currentDocument.co

		if sp > #currentDocument then
			sp = #currentDocument
		elseif sp < 1 then
			sp = 1
		end

		local paragraph = currentDocument[sp]
		if sw > #paragraph then
			sw = #paragraph
		end
		local sl, sw = paragraph:getLineOfWord(sw)
		if not sl then
			sl = #paragraph:wrap().lines
		end
		assert(sl)
		local startlineheight = GetDocumentLineHeightRows(currentDocument,
			paragraph.style)

		local cy = math.floor(ScreenHeight / 2) - sl * startlineheight
		if cp >= sp then
			local p = sp
			while p < cp do
				local wd = currentDocument[p]:wrap()
				cy = cy + #wd.lines * GetDocumentLineHeightRows(
					currentDocument, currentDocument[p].style) +
					currentDocument:spaceBelow(p)
				p = p + 1
			end
			cy = cy + (currentDocument[p]:getLineOfWord(cw, co) - 1) *
				GetDocumentLineHeightRows(currentDocument,
					currentDocument[p].style)
			if cy >= (ScreenHeight - 5) then
				currentDocument._sp = cp
				currentDocument._sw = cw
				return RedrawScreen()
			end
		else
			local p = sp
			while p > cp do
				p = p - 1
				local wd = currentDocument[p]:wrap()
				cy = cy - #wd.lines * GetDocumentLineHeightRows(
					currentDocument, currentDocument[p].style) -
					currentDocument:spaceBelow(p)
			end
			cy = cy + (currentDocument[p]:getLineOfWord(cw, co) - 1) *
				GetDocumentLineHeightRows(currentDocument,
					currentDocument[p].style)
			if cy < 4 then
				currentDocument._sp = cp
				currentDocument._sw = cw
				return RedrawScreen()
			end
		end

		-- Position the cursor.
		do
			local paragraph = currentDocument[cp]
			local wd = paragraph:wrap()
			local word = paragraph[cw]
			local cl = paragraph:getLineOfWord(cw, currentDocument.co)
			local wordx = paragraph:getXOffsetOfWord(cw, currentDocument.co)
			GotoXY(tx + wordx +
				GetWidthFromOffset(word, currentDocument.co) +
				paragraph:getIndentOfLine(cl),
				cy)
		end

		local function clear_jump(y1, y2)
			if (y1 <= y2) and (y2 >= 0) and (y1 < status_y) then
				y1 = math.max(0, y1)
				y2 = math.min(status_y - 1, y2)
				SetNormal()
				ClearArea(lm, y1, rm, y2)
			end
		end

		local function drawline_jump(paragraph, line, ln, y_pos, p_num)
			if (y_pos < 0) or (y_pos >= status_y) then
				return
			end
			local x = paragraph:getIndentOfLine(ln)

			setparacolour(paragraph)
			clear_jump(y_pos, y_pos)
			if not mp then
				paragraph:renderLine(line, tx + x, y_pos)
			else
				paragraph:renderMarkedLine(line, tx + x, y_pos, nil, p_num)
			end

			if (ln == 1) then
				drawmargin(y_pos, p_num, paragraph)
			end

			lineindex[y_pos] = {
				p = p_num,
				w = paragraph:getWordOfLine(ln),
				x = tx
			}
		end

		-- Draw backwards from sp - 1
		local pn = sp - 1
		local sa = currentDocument:spaceAbove(sp)
		local y = math.floor(ScreenHeight / 2) - sl * startlineheight - 1 - sa
		local paragraph = currentDocument[sp]
		if paragraph then
			SetColour(Palette.Paper, Palette.Paper)
			clear_jump(y + 1, y + sa)
		end

		currentDocument._topp = nil
		currentDocument._topw = nil
		currentDocument._topy = nil

		while (y >= 0) do
			local paragraph = currentDocument[pn]
			if not paragraph then
				break
			end

			local wd = paragraph:wrap()
			local lineheight = GetDocumentLineHeightRows(currentDocument,
				paragraph.style)
			for ln = #wd.lines, 1, -1 do
				local l = wd.lines[ln]
				drawline_jump(paragraph, l, ln, y, pn)

				currentDocument._topp = pn
				currentDocument._topw = l.wn
				currentDocument._topy = y
				y = y - lineheight

				if (y < 0) then
					break
				end
			end

			local sa = currentDocument:spaceAbove(pn)
			y = y - sa
			SetColour(Palette.Paper, Palette.Paper)
			clear_jump(y + 1, y + sa)
			pn = pn - 1
		end

		if (y >= 0) and has_terminators then
			drawtopmarker(y)
		end

		-- Draw forwards from sp
		y = math.floor(ScreenHeight / 2) - sl * startlineheight
		pn = sp
		currentDocument._boty = nil
		while (y < status_y) do
			local paragraph = currentDocument[pn]
			if not paragraph then
				break
			end

			drawmargin(y, pn, paragraph)

			local wd = paragraph:wrap()
			local lineheight = GetDocumentLineHeightRows(currentDocument,
				paragraph.style)
			for ln, l in ipairs(wd.lines) do
				drawline_jump(paragraph, l, ln, y, pn)

				if not currentDocument._topp and (y == 0) then
					currentDocument._topp = pn
					currentDocument._topw = l.wn
					currentDocument._topy = y
				end

				currentDocument._botp = pn
				currentDocument._botw = l.wn
				currentDocument._boty = y
				y = y + lineheight

				if (y >= status_y) then
					break
				end
			end
			local sb = currentDocument:spaceBelow(pn)
			y = y + sb
			SetColour(Palette.Paper, Palette.Paper)
			clear_jump(y - sb, y - 1)
			pn = pn + 1
		end

		if not currentDocument._topp then
			currentDocument._topp = 1
			currentDocument._topw = 1
			currentDocument._topy = 0
		end
		if not currentDocument._boty then
			currentDocument._boty = currentDocument._topy
		end

		if (y < status_y) and has_terminators then
			drawbottommarker(y)
		end
	end

	redrawstatus()
	drawscrollbar(scrollbar_top, scrollbar_bottom)

	FireEvent("Redraw")
end

function GetPositionOfLine(y)
	local r = nil
	for yy = 1, y do
		r = lineindex[yy] or r
	end
	return r
end

function GetCharWithBlinkingCursor(timeout)
	ShowCursor()

	timeout = timeout or 1E10
	assert(timeout)

	local shown = true
	while timeout > 0 do
		local t = shown and BLINK_ON_TIME or BLINK_OFF_TIME
		t = math.min(t, timeout)
		local c = wg.getchar(t)
		if (c ~= "KEY_TIMEOUT") then
			ShowCursor();
			return c
		end

		shown = not shown
		local cb = shown and ShowCursor or HideCursor
		cb()

		timeout = timeout - t
	end

	return "KEY_TIMEOUT"
end

-----------------------------------------------------------------------------
-- Does assorted fast updates in the current document on changes:
--   - word count
--   - numbered paragraph styles

do
	local function cb(event, token)
		currentDocument:renumber()
	end

	AddEventListener("Changed", cb)
end
