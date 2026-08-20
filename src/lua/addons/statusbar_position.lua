--!nonstrict
-- © 2015 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local string_format = string.format

-----------------------------------------------------------------------------
-- Build the status bar.

do
	local function cb(event, token, terms)
		if currentDocument:usesTextBuffer() then
			local size = currentDocument._textbuffer:size()
			local position = currentDocument._textpos or 0
			local percent = size == 0 and 0 or math.floor(position * 100 / size)
			local line = currentDocument._textline and
				("L:"..tostring(currentDocument._textline)) or "L:~"
			terms[#terms+1] = {
				priority=100,
				value=string_format("%s %d%% @%d", line, percent, position)
			}
			return
		end
		terms[#terms+1] =
			{
				priority=100,
				value=string_format("%s: %d/%d",
					currentDocument[currentDocument.cp].style,
					currentDocument.cp,
					#currentDocument)
			}
	end

	AddEventListener("BuildStatusBar", cb)
end
