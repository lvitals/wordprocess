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

-- Sized to the styles this document actually uses, not the widest name in
-- documentStyles -- reserving room for every style that exists (e.g. "PRE",
-- "RAW") regardless of whether the document ever uses them would waste
-- columns on documents that only ever use short style names like "P".
local function measureStyleNameMarginWidth(document)
	local m = 0

	if document:usesTextBuffer() then
		local metadata = document:ensureDocumentIndex()
		for _, span in ipairs(metadata and metadata.paragraphStyles or {}) do
			local mm = GetStringWidth(span.style)
			if (mm > m) then
				m = mm
			end
		end
		if (m == 0) then
			-- No style spans recorded yet: match the style
			-- largeParagraphStyleAt() falls back to for untagged text.
			m = GetStringWidth(document:largeParagraphStyleAt(0))
		end
	else
		for _, paragraph in ipairs(document) do
			local mm = GetStringWidth(paragraph.style)
			if (mm > m) then
				m = mm
			end
		end
	end

	return m
end

local function measureParagraphNumberMarginWidth(document)
	if document:usesTextBuffer() then
		local line = document:getLineAtPosition()
		return #tostring(line or 1)
	end
	return int(math.log(math.max(#document, 1), 10)) + 1
end

--- Computes the margin width a given margin mode needs for a document,
-- without any of the side effects (announcements, event listeners) that
-- attaching that mode as the active controller has. Used to give a freshly
-- created document the right-sized margin for its starting mode, before it
-- ever goes through SetMarginMode.
--
-- @param mode               the margin mode
-- @param document           the document the mode will apply to

function GetMarginWidthForMode(mode, document)
	if mode == 2 then
		return measureStyleNameMarginWidth(document)
	elseif mode == 3 then
		return measureParagraphNumberMarginWidth(document)
	elseif mode == 4 then
		return 3
	end
	return 0
end

local style_name_controller=
{
	attach = function(self)
		local cb = function()
			-- See paragraph_number_controller's cb() below: this listener
			-- stays registered past a document switch, so it must check it's
			-- still the active controller for whatever document is current.
			if marginControllers[currentDocument.viewmode] ~= self then
				return
			end

			local m = measureStyleNameMarginWidth(currentDocument)
			if m ~= currentDocument.margin then
				currentDocument.margin = m
				ResizeScreen()
			end
		end

		self.token = AddEventListener("Changed", cb)
		cb()
		NonmodalMessage("Margin now displays paragraph styles.")
	end,

	detach = function(self)
		if self.token then
			RemoveEventListener(self.token)
			self.token = nil
		end
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

			local nm = measureParagraphNumberMarginWidth(currentDocument)
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

	-- Margin presentation changes metadata, not content or physical layout.
	documentSet:touch(true)
	ResizeScreen()

	-- Remember this as the style to start new documents with, so it isn't
	-- lost the moment a new document set or blank document is created.
	SetDefaultMarginMode(mode)
end

function Cmd.SetViewMode(mode)
	SetMarginMode(mode)
	QueueRedraw()
	return true
end

-- Margin display is an editing preference, not document content: whatever a
-- loaded file happens to carry as viewmode/margin (if anything -- older
-- files predate these fields entirely) must not override the style the user
-- has chosen to work in. Every document that comes in from a load is
-- reset to the persisted default the same way a freshly created one is.
do
	local function cb()
		local mode = GetDefaultMarginMode()
		for _, document in ipairs(documentSet:getDocumentList()) do
			document.viewmode = mode
			document.margin = GetMarginWidthForMode(mode, document)
		end
	end

	AddEventListener("DocumentLoaded", cb)
end
