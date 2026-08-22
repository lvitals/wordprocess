--!nonstrict
-- © 2015 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local GetWordText = wg.getwordtext
local GetCwd = wg.getcwd
local ChDir = wg.chdir

local USER_DICTIONARY_NAME = "User dictionary"
local user_dictionary_cache
local system_dictionary_cache

local function get_spellchecker_settings()
	GlobalSettings.spellchecker = GlobalSettings.spellchecker or {
		enabled = false,
		usesystemdictionary = true,
		useuserdictionary = true,
	}
	return GlobalSettings.spellchecker
end

-----------------------------------------------------------------------------
-- Addon registration. Create the default settings in the documentSet.

do
	local function find_default_dictionary()
		if (ARCH == "windows") then
			return assert(WINDOWS_INSTALL_DIR) .. "/Dictionaries/"
		else
			return DEFAULT_DICTIONARY_PATH
		end
	end

	local function cb()
		get_spellchecker_settings()
		GlobalSettings.userdictionary = GlobalSettings.userdictionary or {}
		-- Spellchecking is an editor preference. Discard the obsolete per-set
		-- settings and migrate words from the old hidden dictionary document.
		if documentSet.addons then
			documentSet.addons.spellchecker = nil
		end
		local legacy
		for _, candidate in ipairs(documentSet.documents or {}) do
			if candidate.name == USER_DICTIONARY_NAME then
				legacy = candidate
				break
			end
		end
		if legacy and #documentSet.documents > 1 then
			local known = GetUserDictionary()
			local migrated = false
			for _, paragraph in ipairs(legacy) do
				if paragraph.style == "V" then
					local word = GetWordSimpleText(paragraph[1])
					if word ~= "" and not known[word] then
						GlobalSettings.userdictionary[#GlobalSettings.userdictionary+1] = word
						known[word], migrated = word, true
					end
				end
			end
			local index = documentSet:_findDocument(USER_DICTIONARY_NAME)
			table.remove(documentSet.documents, index)
			if documentSet._documentIndex then
				documentSet._documentIndex[USER_DICTIONARY_NAME] = nil
			end
			if documentSet.current == legacy then
				documentSet.current = documentSet.documents[1]
				currentDocument = documentSet.current
			end
			user_dictionary_cache = nil
			if migrated then SaveGlobalSettings() end
		end

		GlobalSettings.systemdictionary = GlobalSettings.systemdictionary or {}
		local dictionary_settings = GlobalSettings.systemdictionary
		-- A path selected by the user wins. Otherwise follow the default from
		-- this build, including after an upgrade or Meson reconfiguration.
		if dictionary_settings.custom == false or
			not dictionary_settings.filename then
			dictionary_settings.filename = find_default_dictionary()
		elseif dictionary_settings.custom == nil then
			-- Settings written before the `custom` marker existed cannot tell us
			-- how the path was chosen. Preserve the saved path: silently replacing
			-- a valid dictionary is worse than requiring an explicit reset.
			dictionary_settings.custom = true
		end

		-- Migrate the former single dictionary setting. A custom dictionary is
		-- combined with the installed default so bilingual setups work without
		-- discarding either word list.
		if not dictionary_settings.filenames then
			dictionary_settings.filenames = {}
			local default = find_default_dictionary()
			if dictionary_settings.custom and
				dictionary_settings.filename ~= default then
				dictionary_settings.filenames[#dictionary_settings.filenames+1] = default
			end
			dictionary_settings.filenames[#dictionary_settings.filenames+1] =
				dictionary_settings.filename
		end
	end

	AddEventListener("RegisterAddons", cb)
end

-----------------------------------------------------------------------------
-- Allow the spellchecker to be temporarily disabled (so we don't end up
-- spellchecking dialogue boxes, etc).

function SpellcheckerOff()
	local settings = get_spellchecker_settings()
	local state = settings.enabled
	settings.enabled = false
	return state
end

function SpellcheckerRestore(s)
	local settings = get_spellchecker_settings()
	settings.enabled = s
end

-----------------------------------------------------------------------------
-- Utilities.

function GetUserDictionary()
	if not user_dictionary_cache then
		local c = {}
		for _, word in ipairs(GlobalSettings.userdictionary or {}) do
			c[word] = word
		end
		user_dictionary_cache = c
	end
	assert(user_dictionary_cache)
	return user_dictionary_cache
end

function GetSystemDictionary()
	local settings = GlobalSettings.systemdictionary
	if not system_dictionary_cache then
		local dictionaries = {}
		local filenames = settings.filenames or
			(settings.filename and {settings.filename}) or {}
		for _, filename in ipairs(filenames) do
			NonmodalMessage("Opening dictionary '" .. filename .. "'")
			local buffer, e = wg.opentextbuffer(filename)
			if buffer then
				dictionaries[#dictionaries+1] = {
					kind = "mapped",
					buffer = buffer,
					results = {},
					resultCount = 0,
				}
			else
				NonmodalMessage("Failed to load dictionary '" .. filename
					.. "': " .. assert(e))
			end
		end
		if #dictionaries == 1 then
			system_dictionary_cache = dictionaries[1]
		else
			system_dictionary_cache = {
				kind = "multiple",
				dictionaries = dictionaries,
			}
		end
		QueueRedraw()
	end
	assert(system_dictionary_cache)
	return system_dictionary_cache
end

local function mapped_dictionary_contains(dictionary, word)
	local cached = dictionary.results[word]
	if cached ~= nil then return cached end

	local buffer = dictionary.buffer
	local low, high = 0, buffer:size()
	local found = false
	local maxLineLength = 1024*1024
	while low < high do
		local middle = math.floor(low + (high - low) / 2)
		local reverseLimit = math.max(0, middle - maxLineLength)
		local previous = buffer:rfind(reverseLimit, 10, middle)
		if not previous and reverseLimit > 0 then
			ResetSystemDictionaryCache()
			NonmodalMessage("System dictionary contains an excessively long line.")
			return false
		end
		local lineStart = previous and (previous + 1) or 0
		local forwardLimit = math.min(buffer:size(), lineStart + maxLineLength + 1)
		local newline = buffer:find(lineStart, 10, forwardLimit)
		if not newline and forwardLimit < buffer:size() then
			ResetSystemDictionaryCache()
			NonmodalMessage("System dictionary contains an excessively long line.")
			return false
		end
		local lineEnd = newline or buffer:size()
		if lineEnd - lineStart > maxLineLength then
			-- A word-list line should be tiny. Refuse malformed sparse/corrupt
			-- input rather than allocating an attacker-controlled multi-GiB slice.
			ResetSystemDictionaryCache()
			NonmodalMessage("System dictionary contains an excessively long line.")
			return false
		end
		local candidate = buffer:slice(lineStart, lineEnd - lineStart):gsub("\r$", "")
		if candidate == word then
			found = true
			break
		elseif candidate < word then
			low = newline and (newline + 1) or buffer:size()
		else
			high = lineStart
		end
	end

	-- Cache only a bounded working set from the text being displayed. This is
	-- independent of both dictionary and document size.
	if dictionary.resultCount >= 4096 then
		dictionary.results = {}
		dictionary.resultCount = 0
	end
	dictionary.results[word] = found
	dictionary.resultCount = dictionary.resultCount + 1
	return found
end

local function system_dictionary_contains(dictionary, word)
	if dictionary.kind == "mapped" then
		return mapped_dictionary_contains(dictionary, word)
	elseif dictionary.kind == "multiple" then
		for _, item in ipairs(dictionary.dictionaries) do
			if system_dictionary_contains(item, word) then return true end
		end
		return false
	end
	return dictionary[word] == word
end

function ResetSystemDictionaryCache()
	local function close(dictionary)
		if dictionary.kind == "mapped" then
			dictionary.buffer:close()
		elseif dictionary.kind == "multiple" then
			for _, item in ipairs(dictionary.dictionaries) do close(item) end
		end
	end
	if system_dictionary_cache then
		close(system_dictionary_cache)
	end
	system_dictionary_cache = nil
end

function SetSystemDictionaryForTesting(array)
	ResetSystemDictionaryCache()
	local c = {}
	system_dictionary_cache = c

	for _, w in ipairs(array) do
		c[w] = w
	end
end

function IsWordMisspelt(word, firstword)
	local settings = get_spellchecker_settings()
	if settings.enabled then
		local misspelt = true
		local systemdict = {}
		if settings.usesystemdictionary then
			systemdict = GetSystemDictionary()
		end
		local userdict = {}
		if settings.useuserdictionary then
			userdict = GetUserDictionary()
		end
		local scs = GetWordSimpleText(word)
		local sci = scs:lower()
		if (sci == "")
			or (not sci:find("[a-zA-Z]"))
			-- If the capitalisation matches.
			or system_dictionary_contains(systemdict, scs)
			or (userdict[scs] == scs)
			-- If the capitalisation does not match, but this is the first word of a sentence.
			or (firstword and OnlyFirstCharIsUppercase(scs) and
				system_dictionary_contains(systemdict, sci))
			or (firstword and OnlyFirstCharIsUppercase(scs) and (userdict[sci] == sci))
		then
			misspelt = false
		end
		return misspelt
	else
		return false
	end
end

-----------------------------------------------------------------------------
-- Add the current word to the user dictionary.

local MAPPED_SPELL_WINDOW = 1024*1024

local function mapped_word_at_cursor()
	local buffer = currentDocument._textbuffer
	local size = buffer:size()
	local centre = math.min(currentDocument._textpos, size)
	local start = math.max(0, centre - MAPPED_SPELL_WINDOW)
	local finish = math.min(size, centre + MAPPED_SPELL_WINDOW)
	local text = buffer:slice(start, finish-start)
	local relative = centre - start + 1
	for first, word, after in text:gmatch("()(%S+)()") do
		if relative >= first and relative <= after then
			return word, start + first - 1, start + after - 1
		end
	end
	return ""
end

local function add_word_to_user_dictionary(word)
	word = GetWordSimpleText(word)
	if word == "" then return true end
	if (not GetUserDictionary()[word]) and
		(not system_dictionary_contains(GetSystemDictionary(), word)) then
		local words = GlobalSettings.userdictionary
		words[#words+1] = word
		user_dictionary_cache = nil
		SaveGlobalSettings()
		NonmodalMessage("Word '"..word.."' added to user dictionary")
	else
		NonmodalMessage("Word '"..word.."' already in user dictionary")
	end
	QueueRedraw()
	return true
end

function Cmd.AddToUserDictionary()
	if currentDocument:usesTextBuffer() then
		return add_word_to_user_dictionary(mapped_word_at_cursor())
	end
	local word = GetWordSimpleText(currentDocument[currentDocument.cp][currentDocument.cw])
	return add_word_to_user_dictionary(word)
end

-----------------------------------------------------------------------------
-- The core of the live checker: looks up a word and determines whether
-- it's misspelt or not.

do
	local function cb(self, token, payload)
		-- `word` is the visual fragment and may end in a hyphen inserted only
		-- for line wrapping. Check the complete stored word when supplied.
		if IsWordMisspelt(payload.spellingWord or payload.word,
			payload.firstword) then
			-- Keep errors legible instead of dimming them into the background.
			payload.cstyle = bit32.bor(payload.cstyle, wg.UNDERLINE)
			payload.fg = Palette.MisspeltFG
		end
	end

	AddEventListener("DrawWord", cb)
end

-----------------------------------------------------------------------------
-- The core of the offline checker: scan forward looking for misspelt words.

function Cmd.FindNextMisspeltWord()
	if currentDocument:usesTextBuffer() then
		ImmediateMessage("Searching...")
		local buffer = currentDocument._textbuffer
		local size = buffer:size()
		local start = currentDocument._textmark and
			math.max(currentDocument._textmark, currentDocument._textpos) or
			currentDocument._textpos
		local ranges = {{start, size}, {0, start}}
		for _, range in ipairs(ranges) do
			local position = range[1]
			while position < range[2] do
				local length = math.min(MAPPED_SPELL_WINDOW, range[2]-position)
				local text = buffer:slice(position, length)
				local consumed = #text
				if position + length < range[2] and not text:sub(-1):match("%s") then
					local boundary = text:match("^.*()%s")
					if boundary then consumed = boundary end
				end
				if consumed == 0 then consumed = #text end
				local window = text:sub(1, consumed)
				for first, word, after in window:gmatch("()(%S+)()") do
					local absolute = position + first - 1
					local previous = absolute == 0 and "" or buffer:slice(absolute-1, 1)
					local firstword = absolute == 0 or previous == "\n" or previous == "\r"
					if IsWordMisspelt(word, firstword) then
						currentDocument._textmark = absolute
						currentDocument._textpos = position + after - 1
						currentDocument.mp = 1
						NonmodalMessage("Misspelt word found.")
						QueueRedraw()
						return true
					end
				end
				position = position + math.max(consumed, 1)
			end
		end
		currentDocument._textmark = nil
		QueueRedraw()
		NonmodalMessage("No misspelt words found.")
		return false
	end
	ImmediateMessage("Searching...")

	-- If we have a selection, start checking from immediately
	-- afterwards. Otherwise, start at the current cursor position.

	local sp, sw, so
	if currentDocument.mp then
		sp, sw, so = assert(currentDocument.mp), assert(currentDocument.mw) + 1, 1
		if sw > #currentDocument[sp] then
			sw = 1
			sp = sp + 1
			if sp > #currentDocument then
				sp = 1
			end
		end
	else
		sp, sw, so = currentDocument.cp, currentDocument.cw, 1
	end
	local cp, cw, co = sp, sw, so

	-- Keep looping until we reach the starting point again.

	currentDocument[1]:wrap()
	while true do
		local paragraph = currentDocument[cp]
		local word = paragraph[cw]
		local wrapdata = paragraph:wrap()
		if IsWordMisspelt(word, wrapdata.sentences[cw]) then
			currentDocument.cp = cp
			currentDocument.cw = cw
			currentDocument.co = #word + 1
			currentDocument.mp = cp
			currentDocument.mw = cw
			currentDocument.mo = 1
			NonmodalMessage("Misspelt word found.")
			QueueRedraw()
			return true
		end

		-- Nothing. Move on to the next word.

		co = 1
		cw = cw + 1
		if (cw > #currentDocument[cp]) then
			cw = 1
			cp = cp + 1
			if (cp > #currentDocument) then
				cp = 1
			end
			currentDocument[cp]:wrap()
		end

		-- Check to see if we've scanned everything.

		if (cp == sp) and (cw == sw) and (co == 1) then
			break
		end
	end

	QueueRedraw()
	NonmodalMessage("No misspelt words found.")
	return false
end

-----------------------------------------------------------------------------
-- Per-document set configuration user interface.

function Cmd.ConfigureSpellchecker()
	local settings = get_spellchecker_settings()
	local dictionary_settings = GlobalSettings.systemdictionary

	local candidates, seen = {}, {}
	local function add_candidate(filename)
		if filename and filename ~= "" and not seen[filename] then
			seen[filename] = true
			candidates[#candidates+1] = filename
		end
	end
	-- The build default may point at a user dictionary (for example
	-- pt_BR.words), so discover installed system lists independently instead
	-- of treating that default as the only available language.
	local system_word_lists = {
		"/usr/share/dict/words",
		"/usr/share/dict/british-english",
		"/usr/share/dict/spanish",
		"/usr/share/dict/french",
		"/usr/share/dict/ngerman",
		"/usr/share/dict/italian",
		"/usr/share/dict/catala",
		"/usr/share/dict/finnish",
	}
	for _, filename in ipairs(system_word_lists) do
		local info = wg.stat(filename)
		if info and info.mode == "file" then add_candidate(filename) end
	end
	add_candidate(DEFAULT_DICTIONARY_PATH)
	for _, filename in ipairs(dictionary_settings.filenames or {}) do
		add_candidate(filename)
	end
	add_candidate(dictionary_settings.filename)
	for _, name in ipairs(wg.readdir(CONFIGDIR) or {}) do
		if name:match("%.words$") then add_candidate(CONFIGDIR.."/"..name) end
	end
	table.sort(candidates)

	local selected = {}
	for _, filename in ipairs(dictionary_settings.filenames or {}) do
		selected[filename] = true
	end

	local language_names = {
		en = "English", en_US = "English (United States)",
		en_GB = "English (United Kingdom)",
		pt = "Português", pt_BR = "Português (Brasil)",
		pt_PT = "Português (Portugal)",
		es = "Español", spanish = "Español",
		fr = "Français", french = "Français",
		de = "Deutsch", ngerman = "Deutsch",
		it = "Italiano", italian = "Italiano",
		["british-english"] = "English (United Kingdom)",
		catala = "Català", finnish = "Suomi",
	}
	local function dictionary_label(filename)
		local basename = filename:match("([^/\\]+)$") or filename
		local code = basename:gsub("%.words$", "")
		local language = language_names[code]
		if basename == "words" then language = "English (system)" end
		language = language or ("Custom — " .. code)
		local displaypath = filename
		if filename:sub(1, #CONFIGDIR) == CONFIGDIR then
			displaypath = "~/.wordprocess" .. filename:sub(#CONFIGDIR + 1)
		end
		return language .. " — " .. displaypath
	end

	local highlight_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 1,
			x2 = -1, y2 = 1,
			label = "",
			value = settings.enabled
		}

	local systemdictionary_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 3,
			x2 = -1, y2 = 3,
			label = "",
			value = settings.usesystemdictionary
		}

	local userdictionary_checkbox =
		Form.Checkbox {
			x1 = 1, y1 = 5,
			x2 = -1, y2 = 5,
			label = "",
			value = settings.useuserdictionary
		}

	local dictionary_items = {}
	local function update_dictionary_label(item)
		item.label = (item.selected and "[x] " or "[ ] ") ..
			dictionary_label(item.filename)
	end
	for _, filename in ipairs(candidates) do
		local item = {
			filename = filename,
			selected = not not selected[filename],
		}
		update_dictionary_label(item)
		dictionary_items[#dictionary_items+1] = item
	end

	local dictionary_browser = Form.Browser {
		x1 = 1, y1 = 8,
		x2 = -1, y2 = -2,
		data = dictionary_items,
		cursor = 1,
	}
	dictionary_browser[" "] = function(self)
		local item = self.data[self.cursor]
		if item then
			item.selected = not item.selected
			update_dictionary_label(item)
			self:draw()
		end
		return "nop"
	end

	local dialogue=
	{
		title = "Configure Spellchecker",
		width = "large",
		height = "large",
		stretchy = false,

		actions = {
			["KEY_RETURN"] = "confirm",
			["KEY_ENTER"] = "confirm",
		},

		widgets = {
			highlight_checkbox,
			systemdictionary_checkbox,
			userdictionary_checkbox,

			Form.Label {
				x1 = 1, y1 = 1,
				x2 = 32, y2 = 1,
				align = "left",
				value = "Display misspelt words:"
			},

			Form.Label {
				x1 = 1, y1 = 3,
				x2 = 32, y2 = 3,
				align = "left",
				value = "Use language dictionaries:"
			},

			Form.Label {
				x1 = 1, y1 = 5,
				x2 = 32, y2 = 5,
				align = "left",
				value = "Use user dictionary:"
			},

			Form.Label {
				x1 = 1, y1 = 7,
				x2 = -1, y2 = 7,
				align = "left",
				value = "Languages — arrows select, SPACE enables/disables several:"
			},

			dictionary_browser,
		}
	}

	local result = Form.Run(dialogue, RedrawScreen,
		"Arrows choose, SPACE toggles, RETURN confirms, "..ESCAPE_KEY.." cancels")
	if not result then
		return false
	end

	settings.enabled = highlight_checkbox.value
	settings.usesystemdictionary = systemdictionary_checkbox.value
	ResetSystemDictionaryCache()
	dictionary_settings.filenames = {}
	for _, item in ipairs(dictionary_items) do
		if item.selected then
			dictionary_settings.filenames[#dictionary_settings.filenames+1] =
				item.filename
		end
	end
	settings.useuserdictionary = userdictionary_checkbox.value
	SaveGlobalSettings()
	return true
end

-----------------------------------------------------------------------------
-- System dictionary configuration interface.

function Cmd.ConfigureSystemDictionary()
	local settings = GlobalSettings.systemdictionary

	local oldcwd = GetCwd()
	local filename = FileBrowser(
		"Load new system dictionary",
		"Select the dictionary file to load.",
		false)
	ChDir(oldcwd)

	if filename then
		ResetSystemDictionaryCache()
		settings.filename = filename
		settings.custom = true
		settings.filenames = settings.filenames or {}
		local found = false
		for _, existing in ipairs(settings.filenames) do
			if existing == filename then found = true break end
		end
		if not found then settings.filenames[#settings.filenames+1] = filename end
		SaveGlobalSettings()
	end

	return true
end
