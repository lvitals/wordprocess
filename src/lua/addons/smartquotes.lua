--!nonstrict
-- © 2015 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local GetStringWidth = wg.getstringwidth
local P = M.P

local function escape(s)
	return (s:gsub("%%", "%%%%"))
end

-----------------------------------------------------------------------------
-- Process incoming key events.

do
	local function cb(event, token, payload)
		local settings = documentSet.addons.smartquotes or {}
		local start_of_word_pattern =
			(P("^") *
			 (P("[\"']") +
			  P(escape(settings.leftdouble)) +
			  P(escape(settings.leftsingle)) +
			  P("%c")
			 )^0 *
			 P("$")
			):compile()

		if settings.notinraw
				and (currentDocument[currentDocument.cp].style ~= "RAW") then
			local value = payload.value
			local word = currentDocument[currentDocument.cp][currentDocument.cw]
			local prefix = word:sub(1, currentDocument.co-1)
			local first = start_of_word_pattern(prefix) ~= nil

			if settings.doublequotes and (value == '"') then
				value = first and settings.leftdouble or settings.rightdouble
			end
			if settings.singlequotes and (value == "'") then
				value = first and settings.leftsingle or settings.rightsingle
			end
			payload.value = value
		end
	end

	AddEventListener("KeyTyped", cb)
end

-----------------------------------------------------------------------------
-- Addon registration. Create the default settings in the documentSet.

do
	local function cb()
		documentSet.addons.smartquotes = documentSet.addons.smartquotes or {
			doublequotes = false,
			singlequotes = false,
			notinraw = true,
			leftdouble = '“',
			rightdouble = '”',
			leftsingle = '‘',
			rightsingle = '’'
		}
	end

	AddEventListener("RegisterAddons", cb)
end

-----------------------------------------------------------------------------
-- Undo any smart quotes.

function UnSmartquotify(s)
	local settings = documentSet.addons.smartquotes or {}
	s = s:gsub(escape(settings.leftdouble), '"')
	s = s:gsub(escape(settings.rightdouble), '"')
	s = s:gsub(escape(settings.leftsingle), "'")
	s = s:gsub(escape(settings.rightsingle), "'")
	return s
end

-----------------------------------------------------------------------------
-- Process the selection.

local function convert_clipboard()
	local settings = documentSet.addons.smartquotes or {}
	local doc = GetClipboard()

	local ld = escape(settings.leftdouble)
	local rd = escape(settings.rightdouble)
	local ls = escape(settings.leftsingle)
	local rs = escape(settings.rightsingle)

	local start_of_word_pattern =
		(P("^") *
		 (P("[\"']") +
		  P(ld) +
		  P(ls) +
		  P("%c")
		 )^0 *
		 P("$")
		):compile()

	for pn = 1, #doc do
		local para = doc[pn]
		if settings.notinraw and (para.style ~= "RAW") then
			local newwords = {}
			for _, w in ipairs(para) do
				w = w:gsub('()(["\'])',
					function(pos, s)
						local prefix = w:sub(1, pos-1)
						local first = start_of_word_pattern(prefix) ~= nil
						if first then
							if (s == "'") then
								return ls
							elseif (s == '"') then
								return ld
							end
						else
							if (s == "'") then
								return rs
							elseif (s == '"') then
								return rd
							end
						end
						return nil
					end)

				newwords[#newwords+1] = w
			end

			doc[pn] = CreateParagraph(para.style, newwords)
		end
	end

	SetClipboard(doc)
	NonmodalMessage("Clipboard smartquotified.")
	return true
end

local function unconvert_clipboard()
	local settings = documentSet.addons.smartquotes or {}
	local clipboard = GetClipboard()

	local ld = escape(settings.leftdouble)
	local rd = escape(settings.rightdouble)
	local ls = escape(settings.leftsingle)
	local rs = escape(settings.rightsingle)

	for pn = 1, #clipboard do
		local para = clipboard[pn]
		if settings.notinraw and (para.style ~= "RAW") then
			local newwords = {}
			for _, w in ipairs(para) do
				w = w:gsub(ld, '"')
				w = w:gsub(rd, '"')
				w = w:gsub(ls, "'")
				w = w:gsub(rs, "'")
				newwords[#newwords+1] = w
			end

			clipboard[pn] = CreateParagraph(para.style, newwords)
		end
	end

	SetClipboard(clipboard)
	NonmodalMessage("Clipboard unsmartquotified.")
	return true
end

function Cmd.Smartquotify()
	if currentDocument:usesTextBuffer() then
		local settings = documentSet.addons.smartquotes or {}
		local first, last = currentDocument:textSelection()
		if not first or last <= first then
			NonmodalMessage("Select text to smartquotify.")
			return false
		end
		if last - first > 16*1024*1024 then
			NonmodalMessage("Smartquote selection is limited to 16 MiB.")
			return false
		end
		local text = currentDocument._textbuffer:slice(first, last-first)
		local replacements = {}
		for offset, quote in text:gmatch('()(["\'])') do
			local absolute = first + offset - 1
			if not (settings.notinraw and
					currentDocument:largeParagraphStyleAt(absolute) == "RAW") then
				local prefix = text:sub(1, offset-1)
				local previous = prefix:sub(-1)
				local opening = previous == "" or previous:match("[%s%c]") or
					previous == '"' or previous == "'"
				local replacement
				if quote == '"' and settings.doublequotes then
					replacement = opening and settings.leftdouble or settings.rightdouble
				elseif quote == "'" and settings.singlequotes then
					replacement = opening and settings.leftsingle or settings.rightsingle
				end
				if replacement then
					replacements[#replacements+1] = {absolute, replacement}
				end
			end
		end
		if #replacements == 0 then return true end
		if not Cmd.Checkpoint() then return false end
		local growth = 0
		for i = #replacements, 1, -1 do
			local position, replacement = table.unpack(replacements[i])
			currentDocument:deleteTextRange(position, 1)
			currentDocument._textbuffer:insert(position, replacement)
			currentDocument:adjustLargeStyleSpans(position, 0, #replacement)
			growth = growth + #replacement - 1
		end
		currentDocument._textmark = first
		currentDocument._textpos = last + growth
		currentDocument._textchanged = true
		documentSet:touch()
		QueueRedraw()
		NonmodalMessage("Selection smartquotified.")
		return true
	end
	return Cmd.Checkpoint() and
		Cmd.Copy(true) and
		convert_clipboard() and
		Cmd.Paste()
end

function Cmd.Unsmartquotify()
	if currentDocument:usesTextBuffer() then
		local settings = documentSet.addons.smartquotes or {}
		local first, last = currentDocument:textSelection()
		if not first or last <= first then
			NonmodalMessage("Select text to unsmartquotify.")
			return false
		end
		if last - first > 16*1024*1024 then
			NonmodalMessage("Smartquote selection is limited to 16 MiB.")
			return false
		end
		local text = currentDocument._textbuffer:slice(first, last-first)
		local replacements = {}
		local quotes = {
			{settings.leftdouble, '"'}, {settings.rightdouble, '"'},
			{settings.leftsingle, "'"}, {settings.rightsingle, "'"}
		}
		for _, pair in ipairs(quotes) do
			local position = 1
			while pair[1] and pair[1] ~= "" do
				local found = text:find(pair[1], position, true)
				if not found then break end
				local absolute = first + found - 1
				if not (settings.notinraw and
						currentDocument:largeParagraphStyleAt(absolute) == "RAW") then
					replacements[#replacements+1] = {absolute, #pair[1], pair[2]}
				end
				position = found + #pair[1]
			end
		end
		table.sort(replacements, function(a, b) return a[1] > b[1] end)
		if #replacements == 0 then return true end
		if not Cmd.Checkpoint() then return false end
		local shrink = 0
		for _, replacement in ipairs(replacements) do
			currentDocument:deleteTextRange(replacement[1], replacement[2])
			currentDocument._textbuffer:insert(replacement[1], replacement[3])
			currentDocument:adjustLargeStyleSpans(replacement[1], 0, 1)
			shrink = shrink + replacement[2] - 1
		end
		currentDocument._textmark = first
		currentDocument._textpos = last - shrink
		currentDocument._textchanged = true
		documentSet:touch()
		QueueRedraw()
		NonmodalMessage("Selection unsmartquotified.")
		return true
	end
	return Cmd.Checkpoint() and
		Cmd.Copy(true) and
		unconvert_clipboard() and
		Cmd.Paste()
end

-----------------------------------------------------------------------------
-- Configuration user interface.

function Cmd.ConfigureSmartQuotes()
	local settings = documentSet.addons.smartquotes

	local single_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 1,
			x2 = -1, y2 = 1,
			label = "Convert single quotes while typing:",
			value = settings.singlequotes
		}

	local double_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 3,
			x2 = -1, y2 = 3,
			label = "Convert double quotes while typing:",
			value = settings.doublequotes
		}

	local leftsingle_textfield =
		Form.TextField {
			x1 = -16, y1 = 5,
			x2 = -11, y2 = 5,
			value = tostring(settings.leftsingle)
		}

	local rightsingle_textfield =
		Form.TextField {
			x1 = -6, y1 = 5,
			x2 = -1, y2 = 5,
			value = tostring(settings.rightsingle)
		}

	local leftdouble_textfield =
		Form.TextField {
			x1 = -16, y1 = 7,
			x2 = -11, y2 = 7,
			value = tostring(settings.leftdouble)
		}

	local rightdouble_textfield =
		Form.TextField {
			x1 = -6, y1 = 7,
			x2 = -1, y2 = 7,
			value = tostring(settings.rightdouble)
		}

	local notinraw_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 9,
			x2 = -1, y2 = 9,
			label = "Don't convert in RAW paragraphs:",
			value = settings.notinraw
		}

	local dialogue=
	{
		title = "Configure Smart Quotes",
		width = "large",
		height = 13,
		stretchy = false,

		actions = {
			["KEY_RETURN"] = "confirm",
			["KEY_ENTER"] = "confirm",
		},

		widgets = {
			single_checkbox,
			double_checkbox,
			leftsingle_textfield,
			rightsingle_textfield,
			leftdouble_textfield,
			rightdouble_textfield,
			notinraw_checkbox,

			Form.Label {
				x1 = 1, y1 = 5,
				x2 = 32, y2 = 5,
				align = "left",
				value = "Text used for single quotes:"
			},

			Form.Label {
				x1 = -19, y1 = 5,
				x2 = -17, y2 = 5,
				align = "left",
				value = "L:"
			},

			Form.Label {
				x1 = -9, y1 = 5,
				x2 = -7, y2 = 5,
				align = "left",
				value = "R:"
			},

			Form.Label {
				x1 = 1, y1 = 7,
				x2 = 32, y2 = 7,
				align = "left",
				value = "Text used for double quotes:"
			},

			Form.Label {
				x1 = -19, y1 = 7,
				x2 = -17, y2 = 7,
				align = "left",
				value = "L:"
			},

			Form.Label {
				x1 = -9, y1 = 7,
				x2 = -7, y2 = 7,
				align = "left",
				value = "R:"
			},

			Form.Label {
				x1 = 1, y1 = 11,
				x2 = -1, y2 = 11,
				align = "centre",
				value = "To apply to existing text, copy and then paste it."
			}
		}
	}

	local result = Form.Run(dialogue, RedrawScreen,
		"SPACE to toggle, RETURN to confirm, "..ESCAPE_KEY.." to cancel")
	if not result then
		return false
	end

	settings.singlequotes = single_checkbox.value
	settings.doublequotes = double_checkbox.value
	settings.leftsingle = leftsingle_textfield.value
	settings.rightsingle = rightsingle_textfield.value
	settings.leftdouble = leftdouble_textfield.value
	settings.rightdouble = rightdouble_textfield.value
	settings.notinrawquotes = notinraw_checkbox.value
	documentSet:touch()

	return true
end
