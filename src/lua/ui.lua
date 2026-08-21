--!nonstrict
-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local int = math.floor
local Write = wg.write
local GotoXY = wg.gotoxy
local ClearArea = wg.cleararea
local SetNormal = wg.setnormal
local SetBold = wg.setbold
local SetBright = wg.setbright
local SetUnderline = wg.setunderline
local SetReverse = wg.setreverse
local SetDim = wg.setdim
local GetStringWidth = wg.getstringwidth
local GetBytesOfCharacter = wg.getbytesofcharacter
local GetBoundedString = wg.getboundedstring
local UseUnicode = wg.useunicode

function DrawStatusLine(s)
	SetReverse()
	ClearArea(0, ScreenHeight-1, ScreenWidth-1, ScreenHeight-1)
	Write(0, ScreenHeight-1, s)
	SetNormal()
end

function DrawBox(x, y, w, h)
	local border = string.rep(UseUnicode() and "─" or "-", w)
	local space = string.rep(" ", w)
	Write(x-1,   y,     UseUnicode() and " ┌" or " +")
	Write(x+w+1, y,     UseUnicode() and "┐ " or "+ ")
	Write(x-1,   y+h+1, UseUnicode() and " └" or " +")
	Write(x+w+1, y+h+1, UseUnicode() and "┘ " or "+ ")

	Write(x+1,   y,     border)
	Write(x+1,   y+h+1, border)

	for i = y+1, y+h do
		Write(x-1, i, UseUnicode() and " │" or " |")
		Write(x+w+1, i, UseUnicode() and "│ " or "| ")
		Write(x+1, i, space)
	end
end

function CentreInField(x, y, w, s)
	s = GetBoundedString(s, w)
	local xo = int((w - GetStringWidth(s)) / 2)
	Write(x+xo, y, s)
end

function LAlignInField(x, y, w, s)
	s = GetBoundedString(s, w)
	Write(x, y, s)
end

function RAlignInField(x, y, w, s)
	s = GetBoundedString(s, w)
	local xo = w - GetStringWidth(s)
	Write(x+xo, y, s)
end

function DrawTitledBox(x, y, w, h,
		title, subtitle)
	SetBright()
	DrawBox(x, y, w, h)
	CentreInField(x+1, y, w, title)
	if subtitle then
		SetBold()
		CentreInField(x+1, y+h+1, w, subtitle)
	end
	SetNormal()
end

function ImmediateMessage(text)
	-- Progress messages replace the current screen contents before drawing.
	-- This prevents a later stage (for example pagination after loading) from
	-- being painted as another box on top of a file-browser or prior stage.
	if not _drawingImmediateMessage and type(RedrawScreen) == "function" and
		ScreenWidth > 0 and ScreenHeight > 0 then
		_drawingImmediateMessage = true
		RedrawScreen()
		_drawingImmediateMessage = false
	end
	-- Every synchronous operation uses one visual component. Its geometry and
	-- colours depend only on the current screen, never on message length or on
	-- whichever form happened to draw immediately before it.
	local w = math.min(44, ScreenWidth - 4)
	w = math.max(1, w)
	local x = int((ScreenWidth - w) / 2)
	local y = int(ScreenHeight / 2) - 1
	SetColour(Palette.ControlFG, Palette.ControlBG)
	SetNormal()
	DrawBox(x-1, y, w, 1)
	CentreInField(x, y+1, w, text)
	SetNormal()
	wg.sync()
end

function ModalMessage(title, message)
	local dialogue=
	{
		title = title or "Message",
		width = "large",
		height = 2,
		stretchy = true,

		actions = {
			[" "] = "confirm",
		},

		widgets = {
			Form.WrappedLabel {
				value = message,
				x1 = 1, y1 = 1, x2 = -1, y2 = -3,
			},
		}
	}

	Form.Run(dialogue, RedrawScreen,
		"press SPACE to continue")
	QueueRedraw()
end

function Cmd.ShowKeyboardHelp()
	local rows = {
		{label="NAVIGATION MODE  (Alt-N toggles; Esc then N also enters)"},
	}
	local display = {H="H", J="J", K="K", L="L", B="B", W="W",
		LEFTBRACKET="[", RIGHTBRACKET="]", A="A", E="E", U="U", D="D",
		T="T", G="G", X="X", SHIFT_X="Shift-X", SHIFT_D="Shift-D",
		QUESTION="?"}
	for _, entry in ipairs(GetNavigationModeBindings()) do
		rows[#rows+1] = {label=string.format("%-18s %s", display[entry.key],
			GetMenuActionLabel(entry.binding))}
	end
	rows[#rows+1] = {label="I / Escape         Return to writing mode"}
	rows[#rows+1] = {label="Alt-?             Open this help"}
	rows[#rows+1] = {label="Alt-N             Enter / leave navigation mode"}
	rows[#rows+1] = {label=""}
	rows[#rows+1] = {label="OPTIONAL DIRECT SHORTCUTS (active key map)"}
	for _, entry in ipairs(GetCommandLayerBindings()) do
		local direct = ({H="A^H", J="A^J", K="A^K", L="A^L", B="A^B", W="A^W",
			LEFTBRACKET="A^I", RIGHTBRACKET="A^O",
			A="A^A", E="A^E", U="A^U", D="A^D", T="A^T", G="A^G", X="A^X",
			SHIFT_X="AS^X", SHIFT_D="AS^D"})[entry.key]
		if direct then
			local shown = ({LEFTBRACKET="I", RIGHTBRACKET="O"})[entry.key] or display[entry.key]
			rows[#rows+1] = {label=string.format("%-18s %s", "Ctrl-Alt-"..shown,
				GetShortcutActionLabel(direct))}
		end
	end

	rows[#rows+1] = {label=""}
	rows[#rows+1] = {label="ACTIVE STANDARD SHORTCUTS"}
	local standard = {
		{"Left", "LEFT"}, {"Right", "RIGHT"}, {"Up", "UP"}, {"Down", "DOWN"},
		{"Ctrl-Left", "^LEFT"}, {"Ctrl-Right", "^RIGHT"},
		{"Ctrl-Up", "^UP"}, {"Ctrl-Down", "^DOWN"},
		{"Home", "HOME"}, {"End", "END"},
		{"Ctrl-Home", "^HOME"}, {"Ctrl-End", "^END"},
		{"Page Up", "PGUP"}, {"Page Down", "PGDN"},
		{"Backspace", "BACKSPACE"}, {"Delete", "DELETE"},
		{"Ctrl-S", "^S"}, {"Ctrl-O", "^O"}, {"Ctrl-Q", "^Q"},
		{"Ctrl-X", "^X"}, {"Ctrl-C", "^C"}, {"Ctrl-V", "^V"},
		{"Ctrl-Z", "^Z"}, {"Ctrl-Y", "^Y"},
		{"Ctrl-F", "^F"}, {"Ctrl-K", "^K"}, {"Ctrl-R", "^R"},
		{"Ctrl-G", "^G"}, {"Ctrl-E", "^E"}, {"Ctrl-W", "^W"},
		{"Ctrl-B", "^B"}, {"Ctrl-I", "^I"}, {"Ctrl-U", "^U"},
		{"Ctrl-N", "^N"}, {"Ctrl-P", "^P"}, {"Ctrl-@", "^@"},
	}
	for _, entry in ipairs(standard) do
		rows[#rows+1] = {label=string.format("%-18s %s",
			entry[1], GetShortcutActionLabel(entry[2]))}
	end
	local browser = Form.Browser {
		focusable = true, type = Form.Browser,
		x1 = 1, y1 = 1, x2 = -1, y2 = -1,
		data = rows, cursor = 1,
	}
	local function browse_as(key)
		return function()
			return browser[key](browser, key)
		end
	end
	Form.Run({
		title = "Keyboard shortcuts", width = "large", height = "large",
		actions = { ["q"] = "cancel", ["Q"] = "cancel",
			["j"] = browse_as("KEY_DOWN"), ["J"] = browse_as("KEY_DOWN"),
			["k"] = browse_as("KEY_UP"), ["K"] = browse_as("KEY_UP"),
			["h"] = browse_as("KEY_PGUP"), ["H"] = browse_as("KEY_PGUP"),
			["l"] = browse_as("KEY_PGDN"), ["L"] = browse_as("KEY_PGDN"),
			["KEY_RETURN"] = "cancel" },
		widgets = { browser },
	}, RedrawScreen, "J/K lines; H/L pages; Esc, Q, or Enter closes")
	QueueRedraw()
end

function PromptForYesNo(title, message)
	local result = nil

	local function rtrue(self)
		result = true
		return "confirm"
	end

	local function rfalse(self)
		result = false
		return "confirm"
	end

	local dialogue=
	{
		title = title or "Message",
		width = "large",
		height = 2,
		stretchy = true,

		actions = {
			["n"] = rfalse,
			["N"] = rfalse,
			["y"] = rtrue,
			["Y"] = rtrue,
		},

		widgets = {
			Form.WrappedLabel {
				value = message,
				x1 = 1, y1 = 1, x2 = -1, y2 = -3,
			},
		}
	}

	Form.Run(dialogue, RedrawScreen,
		"Y for yes, N for no, or "..ESCAPE_KEY.." to cancel")
	QueueRedraw()
	return result
end

function PromptForString(title, message, default)
	if not default then
		default = ""
	end
	assert(default)

	local textfield =
	Form.TextField {
		value = default,
		cursor = default:len() + 1,
		x1 = 1, y1 = -4, x2 = -1, y2 = -3,
	}

	local dialogue=
	{
		title = title,
		width = "large",
		height = 4,
		stretchy = true,

		actions = {
			["KEY_RETURN"] = "confirm",
			["KEY_ENTER"] = "confirm",
		},

		widgets = {
			Form.WrappedLabel {
				value = message,
				x1 = 1, y1 = 1, x2 = -1, y2 = -6,
			},

			textfield,
		}
	}

	local result = Form.Run(dialogue, RedrawScreen,
		"RETURN to confirm, "..ESCAPE_KEY.." to cancel")

	QueueRedraw()
	if result then
		return textfield.value
	else
		return nil
	end
end

function FindAndReplaceDialogue(defaultfind, defaultreplace)
	defaultfind = defaultfind or ""
	defaultreplace = defaultreplace or ""
	assert(defaultfind)
	assert(defaultreplace)

	local findfield = Form.TextField {
		value = defaultfind,
		cursor = defaultfind:len() + 1,
		x1 = 11, y1 = 1, x2 = -1, y2 = 2,
	}

	local replacefield = Form.TextField {
		value = defaultreplace,
		cursor = defaultreplace:len() + 1,
		x1 = 11, y1 = 3, x2 = -1, y2 = 4,
	}

	local dialogue=
	{
		title = "Find and Replace",
		width = "large",
		height = 5,

		actions = {
			["KEY_RETURN"] = "confirm",
			["KEY_ENTER"] = "confirm",
		},

		widgets = {
			Form.Label {
				value = "Find:",
				x1 = 1, y1 = 1, x2 = 10, y2 = 1,
				align = "left",
			},

			Form.Label {
				value = "Replace:",
				x1 = 1, y1 = 3, x2 = 10, y2 = 3,
				align = "left",
			},

			findfield,
			replacefield,
		}
	}

	local result = Form.Run(dialogue, RedrawScreen,
		"RETURN to confirm, "..ESCAPE_KEY.." to cancel")

	QueueRedraw()
	if result then
		return findfield.value, replacefield.value
	else
		return nil
	end
end

function AboutDialogue()
	local dialogue=
	{
		title = "About WordProcess",
		width = "large",
		height = 10,

		actions = {
			["KEY_RETURN"] = "confirm",
			["KEY_ENTER"] = "confirm",
			[" "] = "confirm",
		},

		widgets = {
			Form.Label {
				value = "WordProcess "..VERSION,
				x1 = 1, y1 = 1, x2 = -1, y2 = 1,
				align = "centre",
			},

			Form.Label {
				value = (UseUnicode() and "©" or "(c)").." 2026 Leandro V. Catarin",
				x1 = 1, y1 = 2, x2 = -1, y2 = 2,
				align = "centre",
			},

			Form.Label {
				value = "File format version "..FILEFORMAT,
				x1 = 1, y1 = 4, x2 = -1, y2 = 4,
				align = "centre",
			},

			Form.Label {
				value = "A focused word processor for structured writing.",
				x1 = 1, y1 = 6, x2 = -1, y2 = 6,
				align = "centre",
			},

			Form.Label {
				value = "Forked from WordGrinder.",
				x1 = 1, y1 = 7, x2 = -1, y2 = 7,
				align = "centre",
			},

			Form.Label {
				value = "With thanks to David Given for the original work.",
				x1 = 1, y1 = 8, x2 = -1, y2 = 8,
				align = "centre",
			},

		}
	}

	local result = Form.Run(dialogue, RedrawScreen,
		"press SPACE to continue")

	QueueRedraw()
	return nil
end
