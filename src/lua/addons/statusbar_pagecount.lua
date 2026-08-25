--!nonstrict
-- © 2013 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

-----------------------------------------------------------------------------
-- Build the status bar.

do
	local function cb(event, token, terms)
		local pages = currentDocument:getPageCount()
		local page = currentDocument:getPageAtPosition()
		terms[#terms+1] = {
			priority=95,
			mandatory=true,
			value=pages and string.format("Pg: %d/%d", page, pages) or "Pg: ?/?",
			shortvalue=pages and string.format("Pg:%d/%d", page, pages) or "Pg:?/?",
		}
	end

	AddEventListener("BuildStatusBar", cb)
end

-----------------------------------------------------------------------------
-- Addon registration. Create the default settings in the documentSet.

do
	local function cb()
		-- Retain the addon table for file compatibility. Physical pagination is
		-- configured exclusively by Configure Page Layout.
		documentSet.addons.pagecount = documentSet.addons.pagecount or {}
	end

	AddEventListener("RegisterAddons", cb)
end

