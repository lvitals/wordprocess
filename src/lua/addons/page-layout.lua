--!nonstrict
-- Per-document physical page layout and publishing profiles.

local PROFILES = { "Custom", "ABNT", "Book" }

local PROFILE_VALUES = {
	["Custom"] = {
		pageWidthCm = 21.0, pageHeightCm = 29.7,
		marginTopCm = 2.5, marginRightCm = 2.5,
		marginBottomCm = 2.5, marginLeftCm = 2.5,
		fontSizePt = 12, lineSpacing = 1.15,
		specialFontSizePt = 10, specialLineSpacing = 1.0,
		longQuoteIndentCm = 4.0,
	},
	["ABNT"] = {
		pageWidthCm = 21.0, pageHeightCm = 29.7,
		marginTopCm = 3.0, marginRightCm = 2.0,
		marginBottomCm = 2.0, marginLeftCm = 3.0,
		fontSizePt = 12, lineSpacing = 1.5,
		specialFontSizePt = 10, specialLineSpacing = 1.0,
		longQuoteIndentCm = 4.0,
	},
	["Book"] = {
		pageWidthCm = 14.0, pageHeightCm = 21.0,
		marginTopCm = 1.8, marginRightCm = 1.6,
		marginBottomCm = 2.0, marginLeftCm = 2.0,
		fontSizePt = 11, lineSpacing = 1.2,
		specialFontSizePt = 9, specialLineSpacing = 1.0,
		longQuoteIndentCm = 1.0,
	},
}

function GetDocumentPageLayout(document)
	document = document or currentDocument
	if not document.pageLayout then
		document.pageLayout = {}
		for key, value in pairs(PROFILE_VALUES.Custom) do
			document.pageLayout[key] = value
		end
		document.pageLayout.profile = "Custom"
	end
	return document.pageLayout
end

function ApplyPageLayoutProfile(document, profile)
	local values = assert(PROFILE_VALUES[profile])
	local layout = GetDocumentPageLayout(document)
	for key, value in pairs(values) do
		layout[key] = value
	end
	layout.profile = profile
	document._pageIndex = nil
	return layout
end

-- The terminal has no physical DPI, so represent the printable page width
-- using the conventional average glyph width of 0.5 em. Exporters continue
-- to use the exact centimetre values; this conversion is only for the editor
-- paper boundary, wrapping, and ruler.
function GetDocumentTextWidthColumns(document)
	local layout = GetDocumentPageLayout(document)
	local printablecm = layout.pageWidthCm - layout.marginLeftCm -
		layout.marginRightCm
	local cmpercolumn = layout.fontSizePt * 0.0352778 * 0.5
	return math.max(20, math.floor(printablecm / cmpercolumn + 0.5))
end

local CM_TO_PT = 72 / 2.54
local SPECIAL_STYLES = {Q=true, N=true, C=true}

local function layoutsignature(document)
	local l = GetDocumentPageLayout(document)
	return table.concat({l.pageWidthCm, l.pageHeightCm, l.marginTopCm,
		l.marginRightCm, l.marginBottomCm, l.marginLeftCm, l.fontSizePt,
		l.lineSpacing, l.specialFontSizePt, l.specialLineSpacing,
		l.longQuoteIndentCm}, ":")
end

local function mappedmetrics(document)
	local layout = GetDocumentPageLayout(document)
	local columns = GetDocumentTextWidthColumns(document)
	local usableheight = (layout.pageHeightCm - layout.marginTopCm -
		layout.marginBottomCm) * CM_TO_PT
	local rows = math.max(1, math.floor(usableheight /
		(layout.fontSizePt * layout.lineSpacing)))
	return columns, rows
end

function PrepareMappedPageIndex(document)
	if not document or not document:usesTextBuffer() then return nil end
	local columns, rows = mappedmetrics(document)
	local stride = 256
	local offsets, pagecount = document._textbuffer:pageindex(columns, rows, stride)
	local index = {
		signature=layoutsignature(document), pageCount=pagecount,
		pageIndexStride=stride, pageOffsets=offsets,
		columns=columns, rows=rows,
	}
	document:ensureDocumentIndex().pageLayoutIndex = index
	document._pageIndex = index
	return index
end

local function stylemetrics(document, style)
	local layout = GetDocumentPageLayout(document)
	local special = SPECIAL_STYLES[style]
	local fontsize = special and layout.specialFontSizePt or layout.fontSizePt
	local spacing = special and layout.specialLineSpacing or layout.lineSpacing
	local usablecm = layout.pageWidthCm - layout.marginLeftCm - layout.marginRightCm
	if style == "Q" then usablecm = usablecm - layout.longQuoteIndentCm end
	local columns = math.max(1, math.floor(
		usablecm / (fontsize * 0.0352778 * 0.5) + 0.5))
	return columns, fontsize * spacing
end

local function linetarget(lines, pn, line)
	local data = lines[line]
	local offset = data.fragment and data.fragment.start or 1
	return {p=pn, line=line, w=data.wn or data[1] or 1, o=offset}
end

local function buildstructuredpageindex(document)
	local layout = GetDocumentPageLayout(document)
	local usableheight = (layout.pageHeightCm - layout.marginTopCm -
		layout.marginBottomCm) * CM_TO_PT
	usableheight = math.max(1, usableheight)
	local starts = {{p=1, line=1, w=1, o=1}}
	local used = 0
	for pn, paragraph in ipairs(document) do
		local width, lineheight = stylemetrics(document, paragraph.style)
		local lines = paragraph:wrap(width).lines
		local gap = document:spaceAbove(pn) * lineheight
		if used > 0 and used + gap > usableheight then
			starts[#starts+1] = linetarget(lines, pn, 1)
			used = 0
		else
			used = used + gap
		end
		for line = 1, #lines do
			if used > 0 and used + lineheight > usableheight then
				starts[#starts+1] = linetarget(lines, pn, line)
				used = 0
			end
			used = used + lineheight
		end
	end
	return {signature=layoutsignature(document), pageCount=#starts, starts=starts}
end

function EnsureDocumentPageIndex(document)
	document = document or currentDocument
	local signature = layoutsignature(document)
	if document._pageIndex and document._pageIndex.signature == signature then
		return document._pageIndex
	end
	if document:usesTextBuffer() then
		local saved = document:ensureDocumentIndex().pageLayoutIndex
		if saved and saved.signature == signature and saved.pageCount and
			saved.pageIndexStride and saved.columns and saved.rows and
			type(saved.pageOffsets) == "table" and #saved.pageOffsets > 0 then
			document._pageIndex = saved
			return saved
		end
		-- Native mapped documents are never synchronously repaginated by a
		-- status redraw. Use a valid persisted bounded page index when present.
		return nil
	end
	document._pageIndex = buildstructuredpageindex(document)
	return document._pageIndex
end

function GetDocumentPageAtPosition(document, index, position)
	if document:usesTextBuffer() then
		local cursor = position or document._textpos
		local offsets, low, high, checkpoint = index.pageOffsets, 1,
			#index.pageOffsets, 1
		while low <= high do
			local middle = math.floor((low + high) / 2)
			if offsets[middle] <= cursor then checkpoint, low = middle, middle + 1
			else high = middle - 1 end
		end
		local page = (checkpoint - 1) * index.pageIndexStride + 1
		local foundpage = document._textbuffer:pagefind(index.columns, index.rows,
			offsets[checkpoint], page, cursor)
		return foundpage
	end
	local p, w, o = document.cp, document.cw, document.co
	if type(position) == "table" then p, w, o = position.p, position.w, position.o end
	local paragraph = document[p]
	local width = stylemetrics(document, paragraph.style)
	local lines = paragraph:wrap(width).lines
	local line = 1
	for number, data in ipairs(lines) do
		local found = false
		if data.fragment and data.wn == w then
			found = o >= data.fragment.start and o <= data.fragment.finish
		else
			for _, word in ipairs(data) do if word == w then found = true; break end end
		end
		if found then line = number; break end
	end
	local page = 1
	for i, start in ipairs(index.starts) do
		if start.p > p or (start.p == p and start.line > line) then break end
		page = i
	end
	return page
end

function GetDocumentPositionForPage(document, index, page)
	if document:usesTextBuffer() then
		local checkpoint = math.floor((page - 1) / index.pageIndexStride) + 1
		local checkpointpage = (checkpoint - 1) * index.pageIndexStride + 1
		local _, offset = document._textbuffer:pagefind(index.columns, index.rows,
			index.pageOffsets[checkpoint], checkpointpage, nil, page)
		return offset
	end
	local start = assert(index.starts[page])
	return {p=start.p, w=start.w, o=start.o}
end

local function find(list, value)
	for i, item in ipairs(list) do
		if item == value then return i end
	end
	return 1
end

function Cmd.ConfigurePageLayout()
	local layout = GetDocumentPageLayout()
	local profile = Form.Toggle {
		x1 = 1, y1 = 1, x2 = -1, y2 = 1,
		label = "Profile", values = PROFILES,
		value = find(PROFILES, layout.profile),
	}

	local specs = {
		{"Page width (cm)", "pageWidthCm"}, {"Page height (cm)", "pageHeightCm"},
		{"Top margin (cm)", "marginTopCm"}, {"Right margin (cm)", "marginRightCm"},
		{"Bottom margin (cm)", "marginBottomCm"}, {"Left margin (cm)", "marginLeftCm"},
		{"Body font size (pt)", "fontSizePt"}, {"Body line spacing", "lineSpacing"},
		{"Special font size (pt)", "specialFontSizePt"},
		{"Special line spacing", "specialLineSpacing"},
		{"Long quote indent (cm)", "longQuoteIndentCm"},
	}
	local fields, widgets = {}, {profile}
	for i, spec in ipairs(specs) do
		local y = i * 2 + 1
		local field = Form.TextField {
			x1 = -11, y1 = y, x2 = -1, y2 = y,
			value = tostring(layout[spec[2]]),
			numeric = true,
		}
		fields[spec[2]] = field
		widgets[#widgets+1] = Form.Label {
			x1 = 1, y1 = y, x2 = -12, y2 = y,
			align = "left", value = spec[1],
		}
		widgets[#widgets+1] = field
	end
	profile.changed = function(self)
		local values = PROFILE_VALUES[PROFILES[self.value]]
		for key, field in pairs(fields) do
			field.value = tostring(values[key])
			field:draw()
		end
	end

	local dialogue = {
		title = "Configure Page Layout", width = "large", height = 25,
		stretchy = false,
		actions = { ["KEY_RETURN"] = "confirm", ["KEY_ENTER"] = "confirm" },
		widgets = widgets,
	}

	while true do
		local result = Form.Run(dialogue, RedrawScreen,
			"LEFT/RIGHT selects a profile, TAB moves, RETURN saves, "..
			ESCAPE_KEY.." cancels")
		if not result then return false end

		local parsed = {}
		local valid = true
		for key, field in pairs(fields) do
			parsed[key] = tonumber(field.value)
			if not parsed[key] or parsed[key] <= 0 then valid = false end
		end
		if not valid then
			ModalMessage("Parameter error", "All page layout values must be positive numbers.")
		else
			local selected = PROFILES[profile.value]
			local defaults = PROFILE_VALUES[selected]
			for key, value in pairs(parsed) do
				if value ~= defaults[key] then selected = "Custom" end
			end
			for key, value in pairs(parsed) do layout[key] = value end
			layout.profile = selected
			documentSet:touch()
			if currentDocument:usesTextBuffer() then
				ImmediateMessage("Paginating document...")
				PrepareMappedPageIndex(currentDocument)
			end
			ResizeScreen()
			QueueRedraw()
			return true
		end
	end
end
