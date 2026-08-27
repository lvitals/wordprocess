--!nonstrict
-- © 2013 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local SCROLLMODES = { "Fixed", "Jump" }
local WORDWRAPMODES = { "Move word", "Hyphenate" }
local WIDTHMODES = { "Full width", "Column limit", "Page preview" }

-----------------------------------------------------------------------------
-- Fetch the maximum allowed width.

function GetMaximumAllowedWidth(screenwidth)
	local settings = GlobalSettings.lookandfeel
	if not settings or settings.widthmode ~= "Column limit" then
		return screenwidth
	end
	return math.min(screenwidth, settings.maxwidth)
end

function GetEditorWidthMode()
	local settings = GlobalSettings.lookandfeel
	return (settings and settings.widthmode) or "Full width"
end

-----------------------------------------------------------------------------
-- Show the terminators?

function WantTerminators()
	local settings = GlobalSettings.lookandfeel
	if settings then
		return settings.terminators or false
	end
	return true
end

-----------------------------------------------------------------------------
-- Use the dense paragraph layout? (Indents, no space between paragraphs.)

function WantDenseParagraphLayout()
	local settings = GlobalSettings.lookandfeel
	if settings then
		return settings.denseparagraphs or false
	end
	return true
end

-- These used to be one setting (denseparagraphs). Keep that value as the
-- migration fallback, while allowing indentation and vertical spacing to be
-- controlled independently from now on.
function WantFirstLineIndent()
	local settings = GlobalSettings.lookandfeel
	if settings and settings.firstlineindent ~= nil then
		return settings.firstlineindent
	end
	return WantDenseParagraphLayout()
end

function WantParagraphSpacing()
	local settings = GlobalSettings.lookandfeel
	if settings and settings.paragraphspacing ~= nil then
		return settings.paragraphspacing
	end
	return not WantDenseParagraphLayout()
end

function GetWordWrapMode()
	local settings = GlobalSettings.lookandfeel
	if settings then
		local mode = settings.wordwrapmode
		if mode == "Hyphenate long words" then
			return WORDWRAPMODES[2]
		end
		return mode or WORDWRAPMODES[1]
	end
	return WORDWRAPMODES[1]
end

function GetTabWidth()
	local settings = GlobalSettings.lookandfeel
	return math.max(1, math.floor((settings and settings.tabwidth) or 4))
end

function WantTabKey()
	local settings = GlobalSettings.lookandfeel
	return not settings or settings.tabkeyenabled ~= false
end

-----------------------------------------------------------------------------
-- Display an extra space after full stops?

function WantFullStopSpaces()
	local settings = GlobalSettings.lookandfeel
	if settings then
		return settings.fullstopspaces or false
	end
	return false
end

-----------------------------------------------------------------------------
-- The margin display mode (Style -> Margin) new documents should start
-- with -- i.e. whatever was last chosen, so it carries over to the next
-- document set or blank document instead of always resetting to "no
-- margin".

function GetDefaultMarginMode()
	local settings = GlobalSettings.lookandfeel
	return (settings and settings.marginmode) or 1
end

function SetDefaultMarginMode(mode)
	GlobalSettings.lookandfeel.marginmode = mode
	SaveGlobalSettings()
end

-----------------------------------------------------------------------------
-- Get the scroll mode.

function GetScrollMode()
	local settings = GlobalSettings.lookandfeel
	if settings then
		return settings.scrollmode
	end
	return "Fixed"
end

-----------------------------------------------------------------------------
-- Addon registration. Create the default global settings.

do
	local function cb()
		local old = GlobalSettings.lookandfeel or {}
		local firstlineindent = old.firstlineindent
		local paragraphspacing = old.paragraphspacing
		if firstlineindent == nil then
			firstlineindent = old.denseparagraphs or false
		end
		if paragraphspacing == nil then
			paragraphspacing = not (old.denseparagraphs or false)
		end
		if old.wordwrapmode == "Move whole word" then
			old.wordwrapmode = WORDWRAPMODES[1]
		elseif old.wordwrapmode == "Hyphenate long words" then
			old.wordwrapmode = WORDWRAPMODES[2]
		end
		local widthmode = old.widthmode
		if not widthmode then
			widthmode = old.enabled and "Column limit" or "Full width"
		end
		GlobalSettings.lookandfeel = MergeTables(GlobalSettings.lookandfeel,
			{
				enabled = false,
				widthmode = widthmode,
				maxwidth = 80,
				terminators = true,
				denseparagraphs = false,
				firstlineindent = firstlineindent,
				paragraphspacing = paragraphspacing,
				wordwrapmode = WORDWRAPMODES[1],
				tabkeyenabled = true,
				tabwidth = 4,
				palette = "Dark",
				scrollmode = "Fixed",
				fullstopspaces = false,
				marginmode = 1,
			}
		)
		SetTheme(GlobalSettings.lookandfeel.palette)
	end

	AddEventListener("RegisterAddons", cb)
end

-----------------------------------------------------------------------------
-- Configuration user interface.

local function find(list, value)
	for i, k in ipairs(list) do
		if value == k then
			return i
		end
	end
	return nil
end

function Cmd.ConfigureLookAndFeel()
	local settings = GlobalSettings.lookandfeel
	local themes = GetThemes()

	local widthmode_toggle =
		Form.Toggle {
			x1 = 1, y1 = 1,
			x2 = -1, y2 = 1,
			label = "Editor width",
			values = WIDTHMODES,
			value = find(WIDTHMODES, settings.widthmode) or 1
		}

	local maxwidth_textfield =
		Form.TextField {
			x1 = -11, y1 = 3,
			x2 = -1, y2 = 3,
			value = tostring(settings.maxwidth),
			numeric = true,
		}

	local terminators_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 5,
			x2 = -1, y2 = 5,
			label = "Show terminators above and below document",
			value = settings.terminators
		}

	local firstlineindent_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 7,
			x2 = -1, y2 = 7,
			label = "Indent the first line of each paragraph",
			value = settings.firstlineindent
		}

	local paragraphspacing_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 9,
			x2 = -1, y2 = 9,
			label = "Leave a blank line between paragraphs",
			value = settings.paragraphspacing
		}

	local fullstopspaces_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 11,
			x2 = -1, y2 = 11,
			label = "Show an extra space after full stops",
			value = settings.fullstopspaces
		}

	local palette_toggle =
		Form.Toggle {
			x1 = 1, y1 = 13,
			x2 = -1, y2 = 13,
			label = "Colour theme",
			values = themes,
			value = find(themes, settings.palette)
		}

	local scrollmode_toggle =
		Form.Toggle {
			x1 = 1, y1 = 15,
			x2 = -1, y2 = 15,
			label = "Scroll mode",
			values = SCROLLMODES,
			value = find(SCROLLMODES, settings.scrollmode)
		}

	local wordwrap_toggle =
		Form.Toggle {
			x1 = 1, y1 = 17,
			x2 = -1, y2 = 17,
			label = "Word wrapping",
			values = WORDWRAPMODES,
			value = find(WORDWRAPMODES, settings.wordwrapmode) or 1
		}

	local tabkey_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 19,
			x2 = -1, y2 = 19,
			label = "Use TAB to insert editable spaces",
			value = settings.tabkeyenabled
		}

	local tabwidth_textfield =
		Form.TextField {
			x1 = -11, y1 = 21,
			x2 = -1, y2 = 21,
			value = tostring(settings.tabwidth),
			numeric = true,
		}

	local dialogue=
	{
		title = "Configure Look and Feel",
		width = "large",
		height = 23,
		stretchy = false,

		actions = {
			["KEY_RETURN"] = "confirm",
			["KEY_ENTER"] = "confirm",
		},

		widgets = {
			widthmode_toggle,

			Form.Label {
				x1 = 1, y1 = 3,
				x2 = -12, y2 = 3,
				align = "left",
				value = "Maximum allowed width",
			},
			maxwidth_textfield,

			terminators_checkbox,
			firstlineindent_checkbox,
			paragraphspacing_checkbox,
			fullstopspaces_checkbox,
			palette_toggle,
			scrollmode_toggle,
			wordwrap_toggle,
			tabkey_checkbox,
			Form.Label {
				x1 = 1, y1 = 21,
				x2 = -12, y2 = 21,
				align = "left",
				value = "TAB width (spaces, 1-16)",
			},
			tabwidth_textfield,
		}
	}

	while true do
		local result = Form.Run(dialogue, RedrawScreen,
			"SPACE to toggle, RETURN to confirm, "..ESCAPE_KEY.." to cancel")
		if not result then
			return false
		end

		local maxwidth = tonumber(maxwidth_textfield.value)
		local tabwidth = tonumber(tabwidth_textfield.value)
		if not maxwidth or (maxwidth < 20) then
			ModalMessage("Parameter error", "The maximum width must be a valid number that's at least 20.")
		elseif not tabwidth or (tabwidth < 1) or (tabwidth > 16) then
			ModalMessage("Parameter error", "TAB width must be a number from 1 to 16.")
		else
			settings.widthmode = WIDTHMODES[widthmode_toggle.value]
			-- Preserve the old field for older WordProcess versions while the
			-- new selector remains the sole source of editor-width behaviour.
			settings.enabled = settings.widthmode == "Column limit"
			settings.maxwidth = maxwidth
			settings.terminators = terminators_checkbox.value
			settings.firstlineindent = firstlineindent_checkbox.value
			settings.paragraphspacing = paragraphspacing_checkbox.value
			settings.denseparagraphs = settings.firstlineindent and
				not settings.paragraphspacing
			settings.wordwrapmode = WORDWRAPMODES[wordwrap_toggle.value]
			settings.tabkeyenabled = tabkey_checkbox.value
			settings.tabwidth = math.floor(tabwidth)
			settings.fullstopspaces = fullstopspaces_checkbox.value
			settings.palette = themes[palette_toggle.value]
			settings.scrollmode = SCROLLMODES[scrollmode_toggle.value]
			SetTheme(settings.palette)
			SaveGlobalSettings()
			UpdateDocumentStyles()
			for _, document in ipairs(documentSet:getDocumentList()) do
				for _, paragraph in ipairs(document) do
					paragraph._wrapdata = nil
				end
			end
			ResizeScreen()
			QueueRedraw()

			return true
		end
	end

	return false
end
