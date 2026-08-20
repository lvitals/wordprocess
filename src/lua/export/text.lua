--!nonstrict
-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local function callback(writer, document)
	return ExportFileUsingCallbacks(document,
	{
		prologue = function()
		end,

		rawtext = function(s)
			writer(s)
		end,

		text = function(s)
			writer(s)
		end,

		notext = function()
		end,

		italic_on = function()
		end,

		italic_off = function()
		end,

		underline_on = function()
		end,

		underline_off = function()
		end,

		bold_on = function()
		end,

		bold_off = function()
		end,

		list_start = function()
		end,

		list_end = function()
		end,

		paragraph_start = function(para)
		end,

		paragraph_end = function(para)
			writer('\n')
		end,

		epilogue = function()
		end
	})
end

function Cmd.ExportTextFile(filename)
	if currentDocument:usesTextBuffer() then
		if not filename then
			filename = FileBrowser("Export Text File", "Export as:", true)
			if not filename then return false end
			if not filename:match("%.txt$") then filename = filename..".txt" end
		end
		ShowLargeTextSaveMessage(filename)
		local ok, e = currentDocument._textbuffer:save(filename)
		if not ok then
			ModalMessage("Export failed", e or "Unknown error")
			return false
		end
		NonmodalMessage("Text export succeeded.")
		return true
	end
	return ExportFileWithUI(filename, "Export Text File", ".txt",
		callback)
end

function Cmd.ExportToTextString(document)
	document = document or currentDocument
	return ExportToString(document, callback)
end
