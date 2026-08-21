--!nonstrict
-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local function gotobrowser(data, index, values)
	values = values or {page="", line="", percent=""}
	local browser = Form.Browser {
		focusable = true,
		type = Form.Browser,
		x1 = 1, y1 = 2,
		x2 = -1, y2 = -8,
		data = data,
		cursor = index
	}
	local pagefield = Form.TextField {
		x1 = 22, y1 = -6, x2 = 36, y2 = -6,
		value = values.page, numeric = true,
	}
	local linefield = Form.TextField {
		x1 = 22, y1 = -4, x2 = 36, y2 = -4,
		value = values.line, numeric = true,
	}
	local percentfield = Form.TextField {
		x1 = 22, y1 = -2, x2 = 36, y2 = -2,
		value = values.percent, numeric = true,
	}

	local dialogue=
	{
		title = "Go To",
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
				value = "Table of Contents — select a chapter or section:"
			},

			browser,
			Form.Label {x1=1, y1=-6, x2=20, y2=-6, value="Page"},
			pagefield,
			Form.Label {x1=1, y1=-4, x2=20, y2=-4, value="Line"},
			linefield,
			Form.Label {x1=1, y1=-2, x2=20, y2=-2, value="Percentage"},
			percentfield,
			Form.Label {x1=38, y1=-2, x2=39, y2=-2, value="%"},
		}
	}

	local result = Form.Run(dialogue, RedrawScreen,
		"TAB/SHIFT-TAB to change field, RETURN to go, "..ESCAPE_KEY.." to cancel")
	QueueRedraw()
	if result then
		values.page, values.line, values.percent =
			pagefield.value, linefield.value, percentfield.value
		if dialogue.focus == 4 then return {kind="page", value=pagefield.value}, values end
		if dialogue.focus == 6 then return {kind="line", value=linefield.value}, values end
		if dialogue.focus == 8 then
			return {kind="percent", value=percentfield.value}, values
		end
		return {kind="heading", index=browser.cursor}, values
	else
		return nil, values
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
		local indent = string.rep("   ", level - 1)
		data[#data+1] = {
			label=indent..table.concat(number).." "..text,
			target=target,
			level=level,
		}
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

local function positive_integer(value, label)
	if not value:match("^%d+$") then
		return nil, label.." must be a positive whole number."
	end
	local number = tonumber(value)
	if not number or number < 1 then
		return nil, label.." must be a positive whole number."
	end
	return number
end

function Cmd.Goto()
	ImmediateMessage("Preparing table of contents...")
	local data, currentheading = build_contents()
	if #data == 0 then
		data[1] = {label="(No H1-H4 headings in this document)", placeholder=true}
	end
	local values = {page="", line="", percent=""}
	while true do
		local selected
		selected, values = gotobrowser(data, currentheading, values)
		if not selected then return false end
		local position, line, err
		if selected.kind == "heading" then
			local item = data[selected.index]
			if item and not item.placeholder then
				position = item.target
				line = currentDocument:usesTextBuffer() and
					currentDocument:getLineAtPosition(position) or position
			end
			if not position then err = "Select a heading or enter a page, line, or percentage." end
		elseif selected.kind == "line" then
			local number
			number, err = positive_integer(selected.value, "Line")
			if number then position, err = currentDocument:getPositionForLine(number); line = number end
		elseif selected.kind == "page" then
			local number
			number, err = positive_integer(selected.value, "Page")
			if number then position, err = currentDocument:getPositionForPage(number) end
		elseif selected.kind == "percent" then
			if not selected.value:match("^%d+%.?%d*$") then
				err = "Percentage must be a number between 0 and 100."
			else
				local number = tonumber(selected.value)
				position, err = currentDocument:getPositionForPercent(number)
			end
		end
		if position then
			if not line and currentDocument:usesTextBuffer() then
				line = currentDocument:getLineAtPosition(position)
			end
			return currentDocument:gotoNavigationPosition(position, line)
		end
		ModalMessage("Cannot go to requested position", err or "Invalid destination.")
	end
end
