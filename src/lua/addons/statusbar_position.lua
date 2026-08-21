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
			local position = currentDocument._textpos or 0
			local percent = currentDocument:getPositionPercent(position)
			local linenumber, exact = currentDocument:getLineAtPosition(position)
			local line = linenumber and
				("L:"..(exact and "" or "~")..tostring(linenumber)) or "L:~"
			terms[#terms+1] = {
				priority=100,
				mandatory=true,
				value=string_format("%s %d%% @%d", line, percent, position),
				shortvalue=string_format("%s %d%%", line, percent),
			}
			return
		end
		local percent = currentDocument:getPositionPercent()
		terms[#terms+1] =
			{
				priority=100,
				-- Preserve the established style/paragraph field verbatim and
				-- extend it with the shared authoritative percentage.
				value=string_format("%s: %d/%d %d%%",
					currentDocument[currentDocument.cp].style,
					currentDocument.cp,
					#currentDocument,
					percent),
				shortvalue=string_format("L:%d %d%%", currentDocument.cp, percent),
			}
	end

	AddEventListener("BuildStatusBar", cb)
end
