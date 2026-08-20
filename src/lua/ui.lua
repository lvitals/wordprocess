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
	local w = GetStringWidth(text)
	local x = int((ScreenWidth - w) / 2)
	local y = int(ScreenHeight / 2)

	DrawBox(x-2, y-1, w+2, 1)
	Write(x, y, text)
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
