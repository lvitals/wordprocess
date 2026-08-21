--!nonstrict
-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local function gotobrowser(data, index)
	local browser = Form.Browser {
		focusable = true,
		type = Form.Browser,
		x1 = 1, y1 = 2,
		x2 = -1, y2 = -1,
		data = data,
		cursor = index
	}

	local dialogue=
	{
		title = "Table of Contents",
		width = "large",
		height = "large",
		stretchy = false,

		actions = {
			["KEY_RETURN"] = "confirm",
			["KEY_ENTER"] = "confirm",
		},

		widgets = {
			Form.Label {
				x1 = 1, y1 = 1,
				x2 = -1, y2 = 1,
				value = "Select a chapter or section to jump to:"
			},

			browser,
		}
	}

	local result = Form.Run(dialogue, RedrawScreen,
		"RETURN to select item, "..ESCAPE_KEY.." to cancel")
	QueueRedraw()
	if result then
		return browser.cursor
	else
		return nil
	end
end

local function build_contents()
	local data, currentheading = {}, 1
	local levelcount = {0, 0, 0, 0}
	local function append(level, text, target, beforecursor)
		text = text:match("^%s*(.-)%s*$")
		if text == "" then return end
		levelcount[level] = levelcount[level] + 1
		for deeper = level + 1, 4 do levelcount[deeper] = 0 end
		local number = {}
		for depth = 1, level do number[#number+1] = levelcount[depth].."." end
		data[#data+1] = {label=table.concat(number).." "..text, target=target}
		if beforecursor then currentheading = #data end
	end
	if currentDocument:usesTextBuffer() then
		local metadata = currentDocument:ensureDocumentIndex()
		local spans = {}
		for _, span in ipairs(metadata.paragraphStyles or {}) do
			local level = tonumber(tostring(span.style):match("^H([1-4])$"))
			if level then spans[#spans+1] = {span=span, level=level} end
		end
		table.sort(spans, function(a, b) return a.span.start < b.span.start end)
		local seen = {}
		for _, heading in ipairs(spans) do
			local position = heading.span.start
			while position < heading.span.finish do
				while position < heading.span.finish do
					local byte = currentDocument._textbuffer:slice(position, 1)
					if byte ~= "\n" and byte ~= "\r" then break end
					position = position + 1
				end
				if position >= heading.span.finish then break end
				local actualfinish = currentDocument._textbuffer:find(position, 10) or
					currentDocument._textbuffer:size()
				local finish = math.min(actualfinish, position + 4096)
				local text = currentDocument._textbuffer:slice(position, finish-position):gsub("\r$", "")
				if finish < actualfinish then text = text.."…" end
				if not seen[position] then
					append(heading.level, text, position,
						position <= currentDocument._textpos)
					seen[position] = true
				end
				position = actualfinish < currentDocument._textbuffer:size() and
					(actualfinish + 1) or heading.span.finish
			end
		end
	else
		for paran, para in ipairs(currentDocument) do
			local level = tonumber(para.style:match("^H([1-4])$"))
			if level then append(level, para:asString(), paran, paran <= currentDocument.cp) end
		end
	end
	return data, currentheading
end

local function goto_target(target)
	if currentDocument:usesTextBuffer() then
		currentDocument._textpos, currentDocument._texttop = target, target
		currentDocument._textline, currentDocument._texttopline = nil, nil
		Cmd.UnsetMark()
	else
		currentDocument.cp, currentDocument.cw, currentDocument.co = target, 1, 1
	end
	QueueRedraw()
	return true
end

function Cmd.Goto()
	ImmediateMessage("Preparing table of contents...")
	local data, currentheading = build_contents()
	if #data == 0 then
		ModalMessage("No contents available",
			"This document has no heading paragraphs.")
		return false
	end
	local selected = gotobrowser(data, currentheading)
	if selected then return goto_target(data[selected].target) end
	return false
end
