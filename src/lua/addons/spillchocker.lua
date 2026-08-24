--!nonstrict
-- © 2015 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local GetWordText = wg.getwordtext
local GetCwd = wg.getcwd
local ChDir = wg.chdir

local USER_DICTIONARY_NAME = "User dictionary"
local MAX_CACHED_DICTIONARY_LOOKUPS = 4096
-- Match the project's normal streaming block size: pages remain small enough
-- for redraw-time reads while amortising text-buffer calls on large lists.
local DICTIONARY_PAGE_BYTES = 64 * 1024
-- Two leading bytes sharply reduce candidate pages, including for UTF-8 words,
-- while keeping the per-page index bounded and cheap to construct.
local DICTIONARY_INDEX_PREFIX_BYTES = 2
local user_dictionary_cache
local system_dictionary_cache
local composition_cache = {}
local composition_cache_count = 0

function DiscoverSystemDictionaries(directory)
	local dictionaries = {}
	for _, name in ipairs(wg.readdir(directory) or {}) do
		if name:sub(1, 1) ~= "." then
			local filename = directory.."/"..name
			local info = wg.stat(filename)
			-- Package aliases (including /usr/share/dict/words) are symlinks.
			-- Listing only their real files avoids duplicates without knowing any
			-- distribution-specific filename or language in advance.
			if info and info.mode == "file" and not info.symlink then
				dictionaries[#dictionaries+1] = filename
			end
		end
	end
	table.sort(dictionaries)
	return dictionaries
end

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
			not dictionary_settings.filename or dictionary_settings.filename == "" then
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
			if default ~= "" and dictionary_settings.custom and
				dictionary_settings.filename ~= default then
				dictionary_settings.filenames[#dictionary_settings.filenames+1] = default
			end
			if dictionary_settings.filename ~= "" then
				dictionary_settings.filenames[#dictionary_settings.filenames+1] =
					dictionary_settings.filename
			end
		end

		-- Remove aliases saved by older versions. Their targets remain available
		-- as independently selectable entries discovered from DICTIONARY_DIR.
		local filenames = {}
		for _, filename in ipairs(dictionary_settings.filenames) do
			local info = wg.stat(filename)
			if not info or not info.symlink then
				filenames[#filenames+1] = filename
			end
		end
		dictionary_settings.filenames = filenames
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
	if not dictionary.pages then
		dictionary.pages = {}
		local size = buffer:size()
		local start = 0
		while start < size do
			local nominalEnd = math.min(size, start + DICTIONARY_PAGE_BYTES)
			local newline = nominalEnd < size and
				buffer:find(nominalEnd, 10, size) or nil
			local finish = newline and (newline + 1) or size
			local text = buffer:slice(start, finish - start)
			local prefixes = {}
			for line in text:gmatch("[^\r\n]+") do
				prefixes[line:sub(1, DICTIONARY_INDEX_PREFIX_BYTES)] = true
			end
			dictionary.pages[#dictionary.pages+1] = {
				start = start, finish = finish, prefixes = prefixes,
			}
			start = finish
		end
	end

	local found = false
	local prefix = word:sub(1, DICTIONARY_INDEX_PREFIX_BYTES)
	for _, page in ipairs(dictionary.pages) do
		if page.prefixes[prefix] then
			local text = "\n" .. buffer:slice(page.start,
				page.finish - page.start) .. "\n"
			if text:find("\n" .. word .. "\n", 1, true) or
				text:find("\n" .. word .. "\r\n", 1, true) then
				found = true
				break
			end
		end
	end

	-- Cache only a bounded working set from the text being displayed. This is
	-- independent of both dictionary and document size.
	if dictionary.resultCount >= MAX_CACHED_DICTIONARY_LOOKUPS then
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
	composition_cache = {}
	composition_cache_count = 0
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
		local function known(candidate)
			local lower = candidate:lower()
			return system_dictionary_contains(systemdict, candidate) or
				system_dictionary_contains(systemdict, lower) or
				userdict[candidate] == candidate or userdict[lower] == lower
		end
		local function known_composition(candidate)
			local cached = composition_cache[candidate]
			if cached ~= nil then return cached end
			local function remember(result)
				if composition_cache_count >= MAX_CACHED_DICTIONARY_LOOKUPS then
					composition_cache = {}
					composition_cache_count = 0
				end
				composition_cache[candidate] = result
				composition_cache_count = composition_cache_count + 1
				return result
			end
			-- Recognise two-part closed compounds, including CamelCase, only when
			-- both independently derived components occur in a selected dictionary.
			local lower = candidate:lower()
			-- Accept a regular plural only when its singular form is present. This
			-- recovers inflections omitted by generated word lists without inventing
			-- vocabulary or storing language-specific words.
			local singular = lower:match("^(.+)s$")
			if singular and known(singular) then return remember(true) end

			for boundary = 2, #lower do
				local prefix = lower:sub(1, boundary - 1)
				local base = lower:sub(boundary)
				if known(prefix) and known(base) then
					return remember(true)
				end
			end

			-- UI paths and similar technical notation consist of dictionary words
			-- separated by non-ASCII-alphanumeric characters. The separators and
			-- vocabulary are discovered from the token rather than enumerated.
			local count = 0
			for component in candidate:gmatch("[A-Za-z0-9']+") do
				count = count + 1
				if not known(component) then return remember(false) end
			end
			return remember(count > 1)
		end
		local properName = OnlyFirstCharIsUppercase(scs) and
			not scs:find("[’']")
		local internalUppercase = scs:sub(2):find("[A-Z]") ~= nil
		local technicalSyntax =
			word:find("<[^>]+>") ~= nil or
			word:find("%-%-") ~= nil or
			word:find("[\\/]") ~= nil or
			word:find("[()]", 1) ~= nil or
			scs:find(".", 1, true) ~= nil or
			internalUppercase
		local uppercaseIdentifier = scs:find("[A-Z]") and
			not scs:find("[a-z]")
		local compoundIdentifier = scs:find("+", 1, true)
		if compoundIdentifier then
			for component in scs:gmatch("[^+]+") do
				local lower = component:lower()
				local uppercase = component:find("[A-Z]") and
					not component:find("[a-z]")
				if not uppercase and
					not system_dictionary_contains(systemdict, component) and
					not system_dictionary_contains(systemdict, lower) and
					userdict[component] ~= component and userdict[lower] ~= lower then
					compoundIdentifier = false
					break
				end
			end
		end
		if (sci == "")
			or (not sci:find("[a-zA-Z]"))
			-- Title-case words inside a sentence are proper-name candidates.
			or properName
			-- Source fragments, paths, tags, command options, qualified names and
			-- mixed-case identifiers are technical notation rather than prose.
			or technicalSyntax
			-- Uppercase identifiers and '+' compounds are conventional names for
			-- acronyms, keys and shortcuts rather than ordinary prose words.
			or uppercaseIdentifier
			or compoundIdentifier
			-- If the capitalisation matches.
			or system_dictionary_contains(systemdict, scs)
			or (userdict[scs] == scs)
			-- If the capitalisation does not match, but this is the first word of a sentence.
			or (firstword and OnlyFirstCharIsUppercase(scs) and
				system_dictionary_contains(systemdict, sci))
			or (firstword and OnlyFirstCharIsUppercase(scs) and (userdict[sci] == sci))
			-- Composition is the bounded fallback after inexpensive exact checks.
			or known_composition(scs)
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
		composition_cache = {}
		composition_cache_count = 0
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
	for _, filename in ipairs(DiscoverSystemDictionaries(DICTIONARY_DIR)) do
		add_candidate(filename)
	end
	local default_info = wg.stat(DEFAULT_DICTIONARY_PATH)
	if default_info and not default_info.symlink then
		add_candidate(DEFAULT_DICTIONARY_PATH)
	end
	for _, filename in ipairs(dictionary_settings.filenames or {}) do
		local info = wg.stat(filename)
		if not info or not info.symlink then add_candidate(filename) end
	end
	local saved_info = dictionary_settings.filename and
		wg.stat(dictionary_settings.filename)
	if not saved_info or not saved_info.symlink then
		add_candidate(dictionary_settings.filename)
	end
	for _, name in ipairs(wg.readdir(CONFIGDIR) or {}) do
		if name:match("%.words$") then add_candidate(CONFIGDIR.."/"..name) end
	end
	table.sort(candidates)

	local selected = {}
	for _, filename in ipairs(dictionary_settings.filenames or {}) do
		local info = wg.stat(filename)
		if not info or not info.symlink then selected[filename] = true end
	end

	local function dictionary_label(filename)
		local basename = filename:match("([^/\\]+)$") or filename
		local displaypath = filename
		if filename:sub(1, #CONFIGDIR) == CONFIGDIR then
			displaypath = "~/.wordprocess" .. filename:sub(#CONFIGDIR + 1)
		end
		return basename .. " — " .. displaypath
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
