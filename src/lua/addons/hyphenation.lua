--!nonstrict
-- © 2026 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

-- Real hyphenation follows each language's own orthographic rules (Knuth
-- and Liang's pattern algorithm, the same one TeX, LibreOffice and Firefox
-- use), not a fixed set of character-counting rules. This addon implements
-- only that generic, language-independent pattern algorithm; the actual
-- linguistic knowledge -- where English, Portuguese, or any other language
-- permits a break -- comes entirely from external "hyph_LL.dic" pattern
-- files (the standard libhyphen format shipped by the "hyphen-*" system
-- packages and LibreOffice/Firefox dictionary extensions), selected the
-- same way spelling dictionaries already are. No language logic is
-- hardcoded here.

local GetBytesOfCharacter = wg.getbytesofcharacter

local MAX_CACHED_HYPHENATION_LOOKUPS = 4096
local patternset_cache = {}
local point_cache = {}
local point_cache_count = 0

local function get_hyphenation_settings()
	GlobalSettings.hyphenation = GlobalSettings.hyphenation or {}
	return GlobalSettings.hyphenation
end

-----------------------------------------------------------------------------
-- Discovery: the same "scan a directory, let the user pick" flow already
-- used for spelling dictionaries.

function DiscoverHyphenationPatterns(directory)
	local files = {}
	for _, name in ipairs(wg.readdir(directory) or {}) do
		-- "hyph_LL.dic" (or "hyph-LL.dic") is the filename convention every
		-- hyphen-* system package and LibreOffice/Firefox dictionary
		-- extension uses for this exact pattern-file format; matching on it
		-- (rather than any *.dic) avoids picking up an unrelated Hunspell
		-- spelling dictionary that just happens to share the extension.
		if name:lower():match("^hyph[_%-]?.*%.dic$") then
			local filename = directory.."/"..name
			local info = wg.stat(filename)
			if info and info.mode == "file" and not info.symlink then
				files[#files+1] = filename
			end
		end
	end
	table.sort(files)
	return files
end

local function discoveredhyphenationfiles()
	local seen = {}
	local files = {}
	local function add(list)
		for _, f in ipairs(list) do
			if not seen[f] then
				seen[f] = true
				files[#files+1] = f
			end
		end
	end
	-- The build-configured system directory (conventionally /usr/share/hyphen,
	-- installed by the hyphen-* packages), plus the user's own personal
	-- directory (already used for personal dictionaries), so dropping a
	-- pattern file there works without root and without editing settings.
	add(DiscoverHyphenationPatterns(HYPHENATION_DIR))
	add(DiscoverHyphenationPatterns(CONFIGDIR))
	table.sort(files)
	return files
end

-- The files actually in effect: an explicit selection made in Configure
-- Hyphenation, preserved across restarts. Until one is made, an
-- unambiguous single discovered pattern file is used automatically (so a
-- single-language installation just works), but several discovered files
-- are deliberately left unselected rather than blended together sight
-- unseen: mixing languages risks a word being hyphenated at a point some
-- other language's patterns happen to permit but the word's actual
-- language would not.
function GetSelectedHyphenationPatternFiles()
	local settings = get_hyphenation_settings()
	if settings.filenames then
		return settings.filenames
	end
	local discovered = discoveredhyphenationfiles()
	if #discovered == 1 then
		return discovered
	end
	return {}
end

function ResetHyphenationPatternCache()
	patternset_cache = {}
	point_cache = {}
	point_cache_count = 0
end

-----------------------------------------------------------------------------
-- Parsing the classic Knuth/Liang pattern format (one encoding-declaration
-- line, then one pattern per line, e.g. "hy3ph", ".ach4", "1b2a"). This is
-- exactly the format used by TeX, libhyphen, LibreOffice and Firefox.

-- ISO-8859-1's upper half maps identically onto the same range of Unicode
-- code points, so byte >=0x80 becomes the two-byte UTF-8 encoding of that
-- same code point. This is a generic encoding conversion, not specific to
-- any language: every hyphen-* package for a Western European language
-- (English, Portuguese, French, German, Spanish, Italian, Dutch...)
-- declares its patterns in this same single-byte encoding.
local function latin1ToUtf8(s)
	if not s:find("[\128-\255]") then
		return s
	end
	local out = {}
	for i = 1, #s do
		local b = s:byte(i)
		if b < 0x80 then
			out[#out+1] = string.char(b)
		else
			out[#out+1] = string.char(0xC0 + (b >> 6), 0x80 + (b & 0x3F))
		end
	end
	return table.concat(out)
end

local function utf8chars(s)
	local i, n = 1, #s
	return function()
		if i > n then return nil end
		local len = GetBytesOfCharacter(s:byte(i))
		local c = s:sub(i, i + len - 1)
		i = i + len
		return c
	end
end

-- Splits one pattern line into its letters (as a plain string, used as a
-- hash key) and the hyphenation values found between them. `values[gap+1]`
-- is the digit that appeared just before the (gap+1)-th letter in the
-- source line (0 where no digit appeared, per Liang's algorithm).
local function parsepattern(line)
	local letters = {}
	local values = {}
	local gap = 0
	for c in utf8chars(line) do
		local d = tonumber(c)
		if d then
			values[gap + 1] = d
		else
			letters[#letters+1] = c
			gap = #letters
		end
	end
	return table.concat(letters), values, #letters
end

local function loadpatternfile(filename)
	local content, e = wg.readfile(filename)
	if not content then
		return nil, e
	end

	local lines = {}
	for line in (content.."\n"):gmatch("([^\r\n]*)\r?\n") do
		lines[#lines+1] = line
	end
	while lines[#lines] == "" do lines[#lines] = nil end
	if #lines == 0 then
		return nil, "empty file"
	end

	local encoding = lines[1]:gsub("^%s+", ""):gsub("%s+$", ""):upper()
	local convert
	if encoding == "UTF-8" or encoding == "UTF8" then
		convert = function(s) return s end
	elseif encoding == "ISO8859-1" or encoding == "ISO-8859-1" or
		encoding == "LATIN1" then
		convert = latin1ToUtf8
	else
		return nil, "unsupported pattern file encoding '"..encoding.."'"
	end

	local patterns = {}
	local maxlen = 0
	-- LEFTHYPHENMIN/RIGHTHYPHENMIN are an optional part of this same
	-- format: the language's own minimum number of characters required on
	-- each side of a break (English patterns declare 2/3, for instance).
	-- Where present, this is what actually governs the minimum -- not a
	-- fixed number picked here -- so it only falls back to a generic
	-- default for pattern files (or words) that don't say.
	local lefthyphenmin, righthyphenmin
	for i = 2, #lines do
		local line = lines[i]
		if line ~= "" then
			local lm = line:match("^LEFTHYPHENMIN%s+(%d+)%s*$")
			local rm = line:match("^RIGHTHYPHENMIN%s+(%d+)%s*$")
			if lm then
				lefthyphenmin = tonumber(lm)
			elseif rm then
				righthyphenmin = tonumber(rm)
			else
				local letters, values, charcount = parsepattern(convert(line))
				if letters ~= "" then
					patterns[letters] = values
					if charcount > maxlen then maxlen = charcount end
				end
			end
		end
	end
	return {
		patterns = patterns, maxlen = maxlen,
		lefthyphenmin = lefthyphenmin, righthyphenmin = righthyphenmin,
	}
end

local function getpatternset(filename)
	local cached = patternset_cache[filename]
	if cached ~= nil then
		return cached or nil
	end
	local set, e = loadpatternfile(filename)
	if not set then
		NonmodalMessage("Failed to load hyphenation patterns '"..filename..
			"': "..tostring(e))
		patternset_cache[filename] = false
		return nil
	end
	patternset_cache[filename] = set
	return set
end

-----------------------------------------------------------------------------
-- Applying the patterns to a word (Liang's algorithm): every substring of
-- the (dot-padded) word is looked up against the pattern set; each match's
-- values are overlaid onto the corresponding gaps, keeping the maximum
-- value seen at each gap. An odd final value permits a break there.

local function applypatternset(patternset, paddedchars, n, values)
	local maxlen = patternset.maxlen
	local patterns = patternset.patterns
	local matched = false
	for s = 1, n do
		local upper = math.min(maxlen, n - s + 1)
		local substr = paddedchars[s]
		for l = 1, upper do
			if l > 1 then
				substr = substr..paddedchars[s + l - 1]
			end
			local patternvalues = patterns[substr]
			if patternvalues then
				matched = true
				for gap = 0, l do
					local v = patternvalues[gap + 1]
					if v and v > (values[s - 1 + gap] or 0) then
						values[s - 1 + gap] = v
					end
				end
			end
		end
	end
	return matched
end

-- The generic default when no selected pattern file's own
-- LEFTHYPHENMIN/RIGHTHYPHENMIN applies to this word (either because none
-- of them recognise it, or none of them declare one): matches the
-- character-based fallback's own minimum, so the two stay consistent with
-- each other for words no language data covers.
local DEFAULT_HYPHENMIN = 2

-- Computes (and caches) both the linguistically valid interior hyphenation
-- points for `word` and the minimum characters required on each side of a
-- break, according to whichever pattern files are currently selected. Only
-- pattern files that actually recognise some part of the word contribute
-- their LEFTHYPHENMIN/RIGHTHYPHENMIN; the more conservative (larger) of
-- several contributing files wins, the same way the points themselves are
-- the union of what every file permits.
local function computehyphenation(word)
	local cached = point_cache[word]
	if cached ~= nil then return cached end

	local paddedchars = {"."}
	for c in utf8chars(word:lower()) do
		paddedchars[#paddedchars+1] = c
	end
	paddedchars[#paddedchars+1] = "."
	local n = #paddedchars

	local values = {}
	local any = false
	local leftmin, rightmin = DEFAULT_HYPHENMIN, DEFAULT_HYPHENMIN
	for _, filename in ipairs(GetSelectedHyphenationPatternFiles()) do
		local patternset = getpatternset(filename)
		if patternset and applypatternset(patternset, paddedchars, n, values) then
			any = true
			if patternset.lefthyphenmin and patternset.lefthyphenmin > leftmin then
				leftmin = patternset.lefthyphenmin
			end
			if patternset.righthyphenmin and patternset.righthyphenmin > rightmin then
				rightmin = patternset.righthyphenmin
			end
		end
	end

	local points = {}
	if any then
		-- charbyteoffset[k] is the byte offset, within `word`, of
		-- paddedchars[k]; the trailing "." lands one byte past the end.
		local charbyteoffset = {}
		charbyteoffset[1] = 1
		local pos = 1
		for k = 2, n - 1 do
			charbyteoffset[k] = pos
			pos = pos + #paddedchars[k]
		end
		charbyteoffset[n] = pos

		for g = 2, n - 2 do
			if ((values[g] or 0) % 2) == 1 then
				points[#points+1] = charbyteoffset[g + 1]
			end
		end
	end

	local result = {points = points, leftmin = leftmin, rightmin = rightmin}
	if point_cache_count >= MAX_CACHED_HYPHENATION_LOOKUPS then
		point_cache = {}
		point_cache_count = 0
	end
	point_cache[word] = result
	point_cache_count = point_cache_count + 1
	return result
end

-- Returns the byte offsets (in the "fragmentend" sense -- the first byte of
-- the piece that would continue on the next line) of every linguistically
-- valid interior hyphenation point in `word`, according to whichever
-- pattern files are currently selected. Empty if no selected pattern file
-- recognises any part of the word (including when none are selected at
-- all), in which case callers fall back to their own default behaviour.
function GetHyphenationPoints(word)
	return computehyphenation(word).points
end

-- Returns the minimum number of characters required before and after a
-- break in `word`, per whichever selected pattern file(s) recognise it
-- (its own declared LEFTHYPHENMIN/RIGHTHYPHENMIN, not a value fixed here).
function GetHyphenationMinimums(word)
	local result = computehyphenation(word)
	return result.leftmin, result.rightmin
end

-----------------------------------------------------------------------------
-- Addon registration.

do
	local function cb()
		get_hyphenation_settings()
	end
	AddEventListener("RegisterAddons", cb)
end

-----------------------------------------------------------------------------
-- Configuration user interface (mirrors Configure Spellchecker's dictionary
-- browser).

function Cmd.ConfigureHyphenation()
	local settings = get_hyphenation_settings()

	local candidates, seen = {}, {}
	local function add_candidate(filename)
		if filename and filename ~= "" and not seen[filename] then
			seen[filename] = true
			candidates[#candidates+1] = filename
		end
	end
	for _, filename in ipairs(discoveredhyphenationfiles()) do
		add_candidate(filename)
	end
	for _, filename in ipairs(settings.filenames or {}) do
		add_candidate(filename)
	end
	table.sort(candidates)

	local selectedbydefault = not settings.filenames and #candidates == 1
	local selected = {}
	if settings.filenames then
		for _, filename in ipairs(settings.filenames) do
			selected[filename] = true
		end
	end

	local function dictionary_label(filename)
		local basename = filename:match("([^/\\]+)$") or filename
		local displaypath = filename
		if filename:sub(1, #CONFIGDIR) == CONFIGDIR then
			displaypath = "~/.wordprocess"..filename:sub(#CONFIGDIR + 1)
		end
		return basename.." — "..displaypath
	end

	local pattern_items = {}
	local function update_pattern_label(item)
		item.label = (item.selected and "[x] " or "[ ] ")..
			dictionary_label(item.filename)
	end
	for _, filename in ipairs(candidates) do
		local item = {
			filename = filename,
			selected = selectedbydefault or not not selected[filename],
		}
		update_pattern_label(item)
		pattern_items[#pattern_items+1] = item
	end

	local pattern_browser = Form.Browser {
		x1 = 1, y1 = 3,
		x2 = -1, y2 = -2,
		data = pattern_items,
		cursor = 1,
	}
	pattern_browser[" "] = function(self)
		local item = self.data[self.cursor]
		if item then
			item.selected = not item.selected
			update_pattern_label(item)
			self:draw()
		end
		return "nop"
	end

	local dialogue = {
		title = "Configure Hyphenation",
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
				align = "left",
				value = "Hyphenation patterns:",
			},
			Form.Label {
				x1 = 1, y1 = 2,
				x2 = -1, y2 = 2,
				align = "left",
				value = "Arrows select, SPACE toggles. Used in Hyphenate wrap mode.",
			},
			pattern_browser,
		},
	}

	local result = Form.Run(dialogue, RedrawScreen,
		"Arrows choose, SPACE toggles, RETURN confirms, "..ESCAPE_KEY.." cancels")
	if not result then
		return false
	end

	settings.filenames = {}
	for _, item in ipairs(pattern_items) do
		if item.selected then
			settings.filenames[#settings.filenames+1] = item.filename
		end
	end
	ResetHyphenationPatternCache()
	SaveGlobalSettings()
	return true
end
