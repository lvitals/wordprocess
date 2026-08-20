--!nonstrict
-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local int = math.floor
local GetStringWidth = wg.getstringwidth

-- This code defines the various controllers that work the margin displays.
-- It's all a little overengineered, but is really intended to test some
-- modularisation concepts.

local no_margin_controller=
{
	attach = function(self)
		currentDocument.margin = 0
		NonmodalMessage("Hiding margin.")
	end,

	getcontent = function(self, pn, paragraph)
		return nil
	end
}

local style_name_controller=
{
	attach = function(self)
		local m = 0

		for _, style in pairs(documentStyles) do
			local mm = GetStringWidth(style.name)
			if (mm > m) then
				m = mm
			end
		end

		currentDocument.margin = m
		NonmodalMessage("Margin now displays paragraph styles.")
	end,

	getcontent = function(self, pn, paragraph)
		return paragraph.style
	end
}

local paragraph_number_controller=
{
	attach = function(self)
		local cb = function()
			-- This listener is registered once on a module-level singleton
			-- and never scoped to a particular document, so it keeps
			-- firing on every "Changed" event even after the user has
			-- switched to (or loaded) a different document. Only touch
			-- currentDocument.margin while it's actually the active
			-- controller for whatever document is current now -- otherwise
			-- it stomps on other documents' margin/viewmode (leaving a
			-- blank gutter, or reverting "hide margin").
			if marginControllers[currentDocument.viewmode] ~= self then
				return
			end

			local nm
			if currentDocument:usesTextBuffer() then
				-- The exact total line count is intentionally not scanned at open.
				-- Reserve enough room for a useful native line counter anyway.
				nm = 10
			else
				nm = int(math.log(math.max(#currentDocument, 1), 10)) + 1
			end
			if nm ~= currentDocument.margin then
				currentDocument.margin = nm
				ResizeScreen()
			end
		end

		self.token = AddEventListener("Changed", cb)
		cb()
		NonmodalMessage("Margin now displays paragraph numbers.")
	end,

	detach = function(self)
		-- self.token is only set once attach() has actually run in this
		-- session. A document can have viewmode == 3 without that ever
		-- having happened -- e.g. loaded from a file that saved paragraph
		-- numbers as its margin mode last session -- in which case there's
		-- nothing to remove. Asserting self.token here used to make
		-- SetMarginMode(1) ("Hide margin") error out and abort before it
		-- ever reached currentDocument.viewmode = mode, so the margin
		-- never actually hid.
		if self.token then
			RemoveEventListener(self.token)
			self.token = nil
		end
	end,

	getcontent = function(self, pn, paragraph)
		return tostring(pn)
	end
}

local word_count_controller=
{
	attach = function(self)
		currentDocument.margin = 3
		NonmodalMessage("Margin now displays word counts.")
	end,

	getcontent = function(self,
			pn, paragraph)
		return tostring(#paragraph)
	end
}

marginControllers =
{
	[1] = no_margin_controller,
	[2] = style_name_controller,
	[3] = paragraph_number_controller,
	[4] = word_count_controller
}

--- Sets a specific margin mode for the current document.
--
-- @param mode               the new margin mode

function SetMarginMode(mode)
	local controller = marginControllers[currentDocument.viewmode]
	if controller.detach then
		assert(controller.detach)(controller)
	end

	currentDocument.viewmode = mode
	controller = marginControllers[currentDocument.viewmode]
	if controller.attach then
		assert(controller.attach)(controller)
	end

	documentSet:touch()
	ResizeScreen()
end

function Cmd.SetViewMode(mode)
	SetMarginMode(mode)
	QueueRedraw()
	return true
end
