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
			ResizeScreen()
			QueueRedraw()
			return true
		end
	end
end
