--!nonstrict
-- © 2008 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local ParseWord = wg.parseword
local WriteFile = wg.writefile
local bitand = bit32.band
local bitor = bit32.bor
local bitxor = bit32.bxor
local bit = bit32.btest
local time = wg.time
local compress = wg.compress
local decompress = wg.decompress
local writeu8 = wg.writeu8
local readu8 = wg.readu8
local escape = wg.escape
local unescape = wg.unescape
local string_format = string.format
local unpack = rawget(_G, "unpack") or table.unpack

local MAGIC = "WordProcess dumpfile v1: this is not a text file!"
local ZMAGIC = "WordProcess dumpfile v2: this is not a text file!"
local TMAGIC = "WordProcess dumpfile v3: this is a text file; diff me!"
local DOCUMENT_MAGIC = "WordProcess document v1"

local STOP = 0
local TABLE = 1
local BOOLEANTRUE = 2
local BOOLEANFALSE = 3
local STRING = 4
local NUMBER = 5
local CACHE = 6
local NEGNUMBER = 7
local BRIEFWORD = 8

local DOCUMENTSETCLASS = 100
local DOCUMENTCLASS = 101
local PARAGRAPHCLASS = 102
local WORDCLASS = 103
local MENUCLASS = 104

local function writetostreamt(object, write)
	local writeo = function(k, v)
		write(k)
		write(": ")
		write(v)
		write("\n")
	end

	local function save(key, t)
		if (type(t) == "table") then
			local m = GetClass(t)
			if (m ~= Paragraph) and (key ~= ".current") then
				for k, i in ipairs(t) do
					save(key.."."..k, i)
				end

				-- Save the keys in alphabetical order, so we get repeatable
				-- files.
				local keys = {}
				for k in pairs(t) do
					if (type(k) ~= "number") then
						if not k:find("^_") then
							keys[#keys+1] = k
						end
					end
				end
				table.sort(keys)

				for _, k in ipairs(keys) do
					save(key.."."..k, t[k])
				end
			end
		elseif (type(t) == "boolean") then
			writeo(key, tostring(t))
		elseif (type(t) == "string") then
			writeo(key, '"'..escape(t)..'"')
		elseif (type(t) == "number") then
			writeo(key, tostring(t))
		else
			error(string.format("unsupported type %s for key %s", type(t), key))
		end
	end

	local function save_document(i, d)
		write("#")
		write(tostring(i))
		write("\n")

		for _, p in ipairs(d) do
			write(p.style)

			for _, s in ipairs(p) do
				write(" ")
				write(s)
			end

			write("\n")
		end

		write(".")
		write("\n")
	end

	save("", object)

	local class = GetClass(object)
	if class == DocumentSet then
		if object.current then
			save(".current", object:_findDocument(object.current.name))
		end

		for i, d in ipairs(object.documents) do
			save_document(i, d)
		end
	end

	return true
end

function SaveToHeaderlessString(object)
	local ss = {}
	local write = function(s)
		ss[#ss+1] = s
	end

	writetostreamt(object, write)
	return table.concat(ss)
end

function SaveToFile(filename, object)
	-- Write the file to a *different* filename (so that crashes during
	-- writing doesn't corrupt the file).

	local s = DOCUMENT_MAGIC .. "\n" .. SaveToHeaderlessString(object)

	local new_filename = filename..".new"
	local _, e = WriteFile(new_filename, s)
	if e then
		return false, e
	end

	-- At this point, we know the new file has been written correctly.
	-- We can remove the old one and rename the new one to be the old
	-- one. On proper operating systems we could do this in a single
	-- os.rename, but Windows doesn't support clobbering renames.

	wg.remove(filename)
	local r, e = wg.rename(new_filename, filename)
	if e then
		-- Yikes! The old file has gone, but we couldn't rename the new
		-- one...
		return r, e..": the filename of your document has changed"
	end
	return r, e
end

function SaveDocumentSetRaw(filename)
	return SaveToFile(filename, documentSet)
end

-- Mapped saves rebuild indexes and stream output even when there are no text
-- edits, so every real save operation needs visible progress.
function ShowLargeTextSaveMessage(filename)
	if not currentDocument:usesTextBuffer() then return false end
	ImmediateMessage("Saving...")
	return true
end

local LEGACY_LARGE_WP_MAGIC = "WordProcess large document v1"
local LARGE_JOURNAL_MAGIC = "WordProcess large journal v1"

local function MetadataChecksum(data)
	local crc = 0xffffffff
	for i = 1, #data do
		crc = bit32.bxor(crc, data:byte(i))
		for _ = 1, 8 do
			if bit32.band(crc, 1) ~= 0 then
				crc = bit32.bxor(bit32.rshift(crc, 1), 0xedb88320)
			else
				crc = bit32.rshift(crc, 1)
			end
		end
	end
	return bit32.bnot(crc)
end

local function UpdateDocumentIndexes(document)
	local buffer = document._textbuffer
	local word_count, paragraph_count = buffer:stats()
	local stride = 4096
	local offsets = {0}
	local position = 0
	local paragraph = 1
	while position < buffer:size() do
		local newline = buffer:find(position, 10)
		if not newline then break end
		position = newline + 1
		paragraph = paragraph + 1
		if ((paragraph - 1) % stride) == 0 then
			offsets[#offsets+1] = position
		end
	end
	local previous = document:ensureDocumentIndex()
	document.documentIndex = {
		version = 2,
		contentLength = buffer:size(),
		lineCount = paragraph_count,
		wordCount = word_count,
		lineIndexStride = stride,
		lineOffsets = offsets,
		paragraphStyles = previous.paragraphStyles or {count=0},
		characterStyles = previous.characterStyles or {count=0},
	}
	PrepareMappedPageIndex(document)
end

local function BuildLargeWPPrefix(filename)
	local index = currentDocument:ensureDocumentIndex()
	if currentDocument._textchanged or not index.lineCount or
		not EnsureDocumentPageIndex(currentDocument) then
		UpdateDocumentIndexes(currentDocument)
	end
	local metadata = SaveToHeaderlessString(documentSet)
	local function makeheader(contents)
		return DOCUMENT_MAGIC.."\n"..
			string.format("metadata-length: %020d\n", #contents)..
			string.format("metadata-crc32: %08x\n", MetadataChecksum(contents))..
			string.format("content-length: %020d\n", currentDocument._textbuffer:size())..
			"\n"
	end
	-- When only metadata changed, retain the existing content offset by padding
	-- the headerless metadata with ignorable blank lines. This enables the
	-- native save path to atomically reflink the old container and rewrite only
	-- its small prefix instead of copying several GiB.
	if not currentDocument._textchanged and filename == currentDocument._textsource then
		local oldoffset = currentDocument._textbuffer:contentoffset()
		local fixedheader = makeheader("")
		local capacity = oldoffset - #fixedheader
		if capacity >= #metadata then
			metadata = metadata..string.rep("\n", capacity - #metadata)
		end
	end
	local header = makeheader(metadata)
	return header..metadata
end

local function SaveLargeWP(filename)
	if not currentDocument._textchanged and not documentSet._changed and
		filename == currentDocument._textsource and
		not currentDocument._textbuffer:sourcechanged() then
		NonmodalMessage("No changes to save.")
		return true
	end
	local oldname = documentSet.name
	documentSet.name = filename
	-- Index rebuilding can scan billions of bytes. Display progress before that
	-- work starts, not only immediately before the final streaming write.
	ShowLargeTextSaveMessage(filename)
	local prefix = BuildLargeWPPrefix(filename)
	local metadataOnly = not currentDocument._textchanged and
		filename == currentDocument._textsource and
		#prefix == currentDocument._textbuffer:contentoffset()
	local ok, e
	if metadataOnly then
		ok, e = currentDocument._textbuffer:saveprefix(filename, prefix)
	end
	-- Save As, text edits, unsupported platforms, or a metadata journal error
	-- retain the existing atomic streaming/reflink path.
	if not ok then
		ok, e = currentDocument._textbuffer:save(filename, prefix)
	end
	if not ok then
		documentSet.name = oldname
		ModalMessage("Cannot save WordProcess document", e or "Unknown error")
		return false
	end
	currentDocument._textsource = filename
	currentDocument._nativeLarge = true
	currentDocument._textchanged = false
	documentSet:clean()
	NonmodalMessage("WordProcess document saved.")
	return true
end

function Cmd.SaveCurrentDocumentAs(filename)
	if currentDocument:usesTextBuffer() then
		if not filename then
			filename = FileBrowser("Save Text Document As", "Save as:", true,
				currentDocument._textsource)
			if not filename then return false end
		end
		if currentDocument._textbuffer:sourcechanged() then
			if filename == currentDocument._textsource then
				ModalMessage("Source file changed",
					"Saving over the source was stopped because it changed on disk. "..
					"Use Save As to preserve this editor view in another file.")
				return false
			end
			if not currentDocument._textbuffer:sourcesafe() then
				ModalMessage("Source file unavailable",
					"The mapped source was truncated, so it is unsafe to read. "..
					"Save As cannot recover bytes which are no longer mapped.")
				return false
			end
			ModalMessage("Source file changed",
				"The original path changed on disk. Save As will preserve the "..
				"version currently open in the editor without overwriting it.")
		end
		if filename:lower():match("%.wp$") then
			return SaveLargeWP(filename)
		end
		ShowLargeTextSaveMessage(filename)
		local ok, e = currentDocument._textbuffer:save(filename)
		if not ok then
			ModalMessage("Cannot save text document", e or "Unknown error")
			return false
		end
		currentDocument._textsource = filename
		currentDocument._textchanged = false
		documentSet:clean()
		NonmodalMessage("Text document saved.")
		return true
	end
	if not filename then
		filename = FileBrowser("Save Document Set", "Save as:", true)
		if not filename then
			return false
		end
		assert(filename)
		if filename:find("/[^.]*$") then
			filename = filename .. ".wp"
		end
	end
	assert(filename)
	documentSet.name = filename

	ImmediateMessage("Saving...")
	documentSet:clean()
	local r, e = SaveDocumentSetRaw(filename)
	if not r then
		assert(e)
		ModalMessage("Save failed", "The document could not be saved: "..e)
	else
		NonmodalMessage("Save succeeded.")
	end
	return assert(r)
end

function Cmd.SaveCurrentDocument()
	if currentDocument:usesTextBuffer() then
		return Cmd.SaveCurrentDocumentAs(currentDocument._textsource)
	end
	local name= documentSet.name
	if not name then
		name = FileBrowser("Save Document Set", "Save as:", true)
		if not name then
			return false
		end
		assert(name)
		if name:find("/[^.]*$") then
			name = name .. ".wp"
		end
		documentSet.name = name
	end
	assert(name)

	return Cmd.SaveCurrentDocumentAs(name)
end

local function loadfromstream(fp)

	local cache= {}
	local load

	local function populate_table(t)
		local n = assert(tonumber(fp:read("*l")))
		for i = 1, n do
			t[i] = load()
		end

		while true do
			local k = load()
			if not k then
				break
			end

			t[k] = load()
		end

		return t
	end

	local load_cb = {
		["DS"] = function()
			local t= {}
			setmetatable(t, DocumentSet)
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		["D"] = function()
			local t= {}
			setmetatable(t, Document)
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		["P"] = function()
			local t= {}
			setmetatable(t, Paragraph)
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		["W"] = function()
			-- Words used to be objects of their own; they've been replaced
			-- with simple strings.
			local t= {}

			-- Ensure we allocate a cache entry *before* calling
			-- populate_table(), or else the numbers will go all wrong; the
			-- original implementation put t here.
			local cn = #cache + 1
			cache[cn] = {}

			populate_table(t)

			cache[cn] = t.text
			return t.text
		end,

		["M"] = function()
			local t= {}
			setmetatable(t, MenuTree)
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		["T"] = function()
			local t= {}
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		["S"] = function()
			local s = fp:read("*l")
			cache[#cache + 1] = s
			return s
		end,

		["N"] = function()
			local n = tonumber(fp:read("*l"))
			cache[#cache + 1] = n
			return n
		end,

		["B"] = function()
			local s = fp:read("*l")
			s = (s == "T")
			cache[#cache + 1] = s
			return s
		end,

		["."] = function()
			return nil
		end
	}

	load = function()
		local s = fp:read("*l")
		if not s then
			error("unexpected EOF when reading file")
		end

		local n = tonumber(s)
		if n then
			return cache[n]
		end

		local f = load_cb[s]
		if not f then
			error("can't load type "..s)
		end
		return f()
	end

	return load()
end

local function loadfromstreamz(fp)
	local cache= {}
	local load
	local data = decompress(fp:read("*a"))
	local offset = 1

	local function populate_table(t)
		local n
		n, offset = readu8(data, offset)
		for i = 1, n do
			t[i] = load()
		end

		while true do
			local k = load()
			if not k then
				break
			end

			t[k] = load()
		end

		return t
	end

	local load_cb = {
		[CACHE] = function()
			local n
			n, offset = readu8(data, offset)
			return cache[n]
		end,

		[DOCUMENTSETCLASS] = function()
			local t= {}
			setmetatable(t, DocumentSet)
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		[DOCUMENTCLASS] = function()
			local t= {}
			setmetatable(t, Document)
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		[PARAGRAPHCLASS] = function()
			local t= {}
			setmetatable(t, Paragraph)
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		[WORDCLASS] = function()
			-- Words used to be objects of their own; they've been replaced
			-- with simple strings.
			local t= {}

			-- Ensure we allocate a cache slot *before* calling populate_table,
			-- or else the numbers all go wrong.
			local cn = #cache + 1
			cache[cn] = {}

			populate_table(t)

			cache[cn] = t.text
			return t.text
		end,

		[BRIEFWORD] = function()
			-- Words used to be objects of their own; they've been replaced
			-- with simple strings.

			local t= load()
			cache[#cache+1] = t
			return t
		end,

		[MENUCLASS] = function()
			local t= {}
			setmetatable(t, MenuTree)
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		[TABLE] = function()
			local t= {}
			cache[#cache + 1] = t
			return populate_table(t)
		end,

		[STRING] = function()
			local n
			n, offset = readu8(data, offset)
			local s = data:sub(offset, offset+n-1)
			offset = offset + n

			cache[#cache + 1] = s
			return s
		end,

		[NUMBER] = function()
			local n
			n, offset = readu8(data, offset)
			cache[#cache + 1] = n
			return n
		end,

		[NEGNUMBER] = function()
			local n
			n, offset = readu8(data, offset)
			n = -n
			cache[#cache + 1] = n
			return n
		end,

		[BOOLEANTRUE] = function()
			cache[#cache + 1] = true
			return true
		end,

		[BOOLEANFALSE] = function()
			cache[#cache + 1] = false
			return false
		end,

		[STOP] = function()
			return nil
		end
	}

	load = function()
		local n
		n, offset = readu8(data, offset)

		local f = load_cb[n]
		if not f then
			error("can't load type "..n.." at offset "..offset)
		end
		return f()
	end

	return load()
end

local function loadfromstreamt(fp)
	local data = CreateDocumentSet()
	data.menu = CreateMenuTree()
	data.documents = {}

	local function readl()
		local s = fp:read("*l")
		if s then
			return s:gsub("\r", "")
		end
		return nil
	end

	while true do
		local line = readl()
		if not line then
			break
		end
		assert(line)

		if line:find("^%.") then
			local s, _, k, p, v
				= line:find("^(.*)%.([^.:]+): (.*)$")
			if not s then
				error(
					string.format("malformed line when reading file: '%s'", line))
			end

			-- This is setting a property value.
			local o= data
			for e in k:gmatch("[^.]+") do
				local en= e
				if e:find('^[0-9]+$') then
					en = assert(tonumber(e))
				end
				if not o[en] then
					if (o == data.documents) then
						o[en] = CreateDocument()
					else
						o[en] = {}
					end
				end
				o = o[en]
			end

			if v:find('^-?[0-9][0-9.e+-]*$') then
				v = tonumber(v)
			elseif (v == "true") then
				v = true
			elseif (v == "false") then
				v = false
			elseif v:find('^".*"$') then
				v = v:sub(2, -2)
				v = unescape(v)
			else
				error(
					string.format("malformed property %s.%s: %s", k, p, v))
			end

			if p:find('^[0-9]+$') then
				p = tonumber(p)
			end

			o[p] = v
		elseif line:find("^#") then
			local id = line:sub(2)
			local doc
			if id == "clipboard" then
				doc = assert(data.clipboard)
			else
				local n = assert(tonumber(id))
				doc = data.documents[n]
			end

			local index = 1
			while true do
				line = readl()
				if not line or (line == ".") then
					break
				end

				local words = SplitString(line, " ")
				local para = CreateParagraph(unpack(words))

				doc[index] = para
				index = index + 1
			end
		elseif line == "" then
			-- Just ignore these.
		else
			error(
				string.format("malformed line when reading file: '%s'", line))
		end
	end

	-- Bugfix: previously, the document metadata was written twice to the file,
	-- once using the numeric document index as key and once using the name
	-- (because the same table was used for both indices). This was wrong. So
	-- we need to go through and remove the stub documents created erroneously
	-- for the string keys. The actual data is added to the documents with
	-- numeric keys, via the # line above.

	for i, d in pairs(data.documents) do
		if type(i) == "string" then
			data.documents[i] = nil
		end
	end

	-- Create the index by name.
	--
	data._documentIndex = {}
	for i, d in pairs(data.documents) do
		data._documentIndex[d.name] = d
	end
	data.current = data.documents[data.current ]

	-- Remove any clipboard (unused).
	data.clipboard = nil

	return data
end

function LoadFromHeaderlessString(s)
	return loadfromstreamt(CreateIStream(s))
end

function LoadFromString(filename, data)
	local fp = CreateIStream(data)

	local loader = nil
	local firstline = fp:read("*l")
	if not firstline then
		fp:close()
		return nil, ("'"..filename.."' is empty and is not a valid WordProcess file.")
	end
	local magic = firstline:gsub("\r", "")
	if (magic == MAGIC) then
		loader = loadfromstream
	elseif (magic == ZMAGIC) then
		loader = loadfromstreamz
	elseif (magic == TMAGIC) or (magic == DOCUMENT_MAGIC) then
		loader = loadfromstreamt
	else
		fp:close()
		return nil, ("'"..filename.."' is not a valid WordProcess file.")
	end

	return loader(fp)
end

local function LoadLargeWPFromFile(filename)
	local probe = wg.opentextbuffer(filename)
	if not probe then return nil, nil, false end
	local probe_length = math.min(probe:size(), 4096)
	local header = probe:slice(0, probe_length)
	local scalable_magic
	if header:sub(1, #DOCUMENT_MAGIC + 1) == DOCUMENT_MAGIC.."\n" and
			header:sub(#DOCUMENT_MAGIC + 2):match("^metadata%-length:") then
		scalable_magic = DOCUMENT_MAGIC
	elseif header:sub(1, #LEGACY_LARGE_WP_MAGIC + 1) ==
			LEGACY_LARGE_WP_MAGIC.."\n" then
		scalable_magic = LEGACY_LARGE_WP_MAGIC
	end
	if header:match("^WordProcess document v%d+\nmetadata%-length:") and
			not scalable_magic then
		probe:close()
		return nil, "This WordProcess document requires a newer application version", true
	end
	if not scalable_magic then
		probe:close()
		return nil, nil, false
	end

	local metadata_length, metadata_checksum, content_length, content_offset = header:match(
		"^"..scalable_magic:gsub("([^%w])", "%%%1")..
		"\nmetadata%-length: (%d+)\n"..
		"metadata%-crc32: (%x+)\n"..
		"content%-length: (%d+)\n\n()")
	metadata_length = tonumber(metadata_length)
	metadata_checksum = tonumber(metadata_checksum, 16)
	content_length = tonumber(content_length)
	if not metadata_length or not metadata_checksum or not content_length or not content_offset then
		probe:close()
		return nil, "Invalid WordProcess document header", true
	end
	content_offset = content_offset - 1 + metadata_length
	if metadata_length > (16 * 1024 * 1024) or
		content_offset > probe:size() or
		content_length > (probe:size() - content_offset) then
		probe:close()
		return nil, "WordProcess document ranges are invalid", true
	end

	local metadata_start = content_offset - metadata_length
	local metadata = probe:slice(metadata_start, metadata_length)
	probe:close()
	if MetadataChecksum(metadata) ~= metadata_checksum then
		return nil, "WordProcess document metadata checksum failed", true
	end
	local loaded = LoadFromHeaderlessString(metadata)
	if not loaded or not loaded.current then
		return nil, "WordProcess document metadata is invalid", true
	end

	local placeholder = loaded.current
	local mapped, e = CreateTextBufferDocument(filename, content_offset, content_length)
	if not mapped then return nil, e, true end
	for key, value in pairs(placeholder) do
		if type(key) ~= "number" and key:sub(1, 1) ~= "_" then
			mapped[key] = value
		end
	end
	mapped:ensureDocumentIndex()
	if not EnsureDocumentPageIndex(mapped) then
		ImmediateMessage("Loading document: paginating...")
		PrepareMappedPageIndex(mapped)
	end
	mapped._nativeLarge = true
	local index = loaded:_findDocument(placeholder.name)
	loaded.documents[index] = mapped
	loaded._documentIndex[placeholder.name] = mapped
	loaded.current = mapped
	return loaded, nil, true
end

local function LoadLargeJournalFromFile(filename)
	local probe = wg.opentextbuffer(filename)
	if not probe then return nil, nil, false end
	local prefix = probe:slice(0, math.min(probe:size(), #LARGE_JOURNAL_MAGIC + 1))
	probe:close()
	if prefix ~= LARGE_JOURNAL_MAGIC.."\n" then return nil, nil, false end
	local source, content_offset, base_length, metadata = wg.journalinfo(filename)
	if not source then return nil, content_offset, true end
	local loaded = LoadFromHeaderlessString(metadata)
	if not loaded or not loaded.current then
		return nil, "Large-document journal metadata is invalid", true
	end
	local placeholder = loaded.current
	local mapped, e = CreateTextBufferDocument(source, content_offset, base_length)
	if not mapped then
		return nil, "Cannot open journal base file: "..tostring(e), true
	end
	local applied, applyerror = mapped._textbuffer:applyjournal(filename)
	if not applied then mapped._textbuffer:close(); return nil, applyerror, true end
	for key, value in pairs(placeholder) do
		if type(key) ~= "number" and key:sub(1, 1) ~= "_" then mapped[key] = value end
	end
	mapped:ensureDocumentIndex()
	mapped._textsource = source
	mapped._textchanged = true
	mapped._recoveredJournal = filename
	local index = loaded:_findDocument(placeholder.name)
	loaded.documents[index] = mapped
	loaded._documentIndex[placeholder.name] = mapped
	loaded.current = mapped
	loaded:touch()
	return loaded, nil, true
end

function LoadFromFile(filename)
	local recovered, journal_error, is_journal = LoadLargeJournalFromFile(filename)
	if is_journal then return recovered, journal_error end
	local large, large_error, recognized = LoadLargeWPFromFile(filename)
	if recognized then return large, large_error end
	local data, _, e = wg.readfile(filename);
	if not data then
		assert(e)
		return nil, ("'"..filename.."' could not be opened: "..e)
	end
	assert(data)
	return LoadFromString(filename, data)
end

local function loaddocument(filename)
	local d, e = LoadFromFile(filename)
	if e then
		return nil, e
	end

	-- Even if the changed flag was set in the document on disk, remove it.

	assert(d)
	d:clean()

	d.name = filename
	return d
end

function Cmd.LoadDocumentSet(filename)
	if not ConfirmDocumentErasure() then
		return false, "Cancelled"
	end

	if not filename then
		filename = FileBrowser("Load Document Set", "Load file:", false)
		if not filename then
			return false, "Cancelled"
		end
	end

	assert(filename)
	ImmediateMessage("Loading "..filename.."...")
	local d, e = loaddocument(filename)
	if not d then
		if not e then
			e = "The load failed, probably because the file could not be opened."
		end
		assert(e)
		ModalMessage("Load failed", e)
		QueueRedraw()
		return false, e
	end
	assert(d)

	-- Downgrading documents is not supported.
	local fileformat = d.fileformat or 1
	if (fileformat > FILEFORMAT) then
		ModalMessage("Cannot load document", "This document belongs to a newer version of " ..
			"WordProcess and cannot be loaded. Sorry.")
		QueueRedraw()
		return false, "Incompatible version"
	end

	documentSet = d
	currentDocument = d.current

	if (fileformat < FILEFORMAT) then
		UpgradeDocument(fileformat)
		FireEvent("DocumentUpgrade", fileformat, FILEFORMAT)

		documentSet.fileformat = FILEFORMAT
		documentSet.menu = CreateMenuTree()
	end
	FireEvent("RegisterAddons")
	-- Registering missing addon defaults marks the set for compatibility, but
	-- does not alter document content or physical layout. Keep the page index
	-- that was loaded or rebuilt moments ago.
	documentSet:touch(true)

	ResizeScreen()
	FireEvent("DocumentLoaded")

	UpdateDocumentStyles()
	RebuildDocumentsMenu(documentSet.documents)
	QueueRedraw()

	if (fileformat < FILEFORMAT) then
		ModalMessage("Document upgraded",
			"You are trying to open a file belonging to an earlier "..
			"version of WordProcess. That's not a problem, but if you "..
			"save the file again it may not work on the old version. "..
			"Also, all keybindings defined in this file will get reset "..
			"to their default values.")
	end

	-- The document is NOT dirty immediately after a load.

	documentSet._changed = false

	return true
end

function UpgradeDocument(oldversion)
	documentSet.addons = documentSet.addons or {}

	-- Upgrade version 1 to 2.

	if (oldversion < 2) then
		-- Update wordcount.

		for _, document in ipairs(documentSet.documents) do
			local wc = 0

			for _, p in ipairs(document) do
				wc = wc + #p
			end

			document.wordcount = wc
		end

		-- Status bar defaults to on.

		documentSet.statusbar = true
	end

	-- Upgrade version 2 to 3.

	if (oldversion < 3) then
		-- Idle time defaults to 3.

		(documentSet).idletime = 3
	end

	-- Upgrade version 5 to 6.

	if (oldversion < 6) then
		-- This is the version which made WordClass disappear. The
		-- conversion's actually done as part of the stream loader
		-- (where WORDCLASS and BRIEFWORD are parsed).
	end

	-- Upgrade version 6 to 7.

	if (oldversion < 7) then
		-- This is the version where documentSet.styles vanished. Each paragraph.style
		-- is now a string containing the name of the style; styles are looked up on
		-- demand.

        local function convertStyles(document)
            for _, p in ipairs(document) do
                if (type(p.style) ~= "string") then
                    p.style = (p.style).name
                end
            end
        end

		for _, document in ipairs(documentSet.documents) do
            convertStyles(document)
        end
		(documentSet).styles = nil
	end

	-- Upgrade version 7 to 8.

	if (oldversion < 8) then
		-- This version added the LN paragraph style type; documents are forwards
		-- compatible but not backward compatible.

		-- A bug on 0.7.2 meant that the styles were still exported in
		-- WordProcess files, even though they were never used.

		(documentSet).styles = nil
		(documentSet).idletime = nil
	end
end

function GetClipboard()
	local text, wgdata = wg.clipboard_get()
	if wgdata then
		if wgdata:sub(1, 31) == "WordProcess large clipboard v1\n" then
			return text and Cmd.ImportTextString(text) or CreateDocument()
		end
		return LoadFromHeaderlessString(wgdata).documents[1]
	end
	if text then
		return Cmd.ImportTextString(text)
	end
	return CreateDocument()
end

function SetClipboard(document)
	local text = Cmd.ExportToTextString(document)

	local documentSet = CreateDocumentSet()
	document.name = "clipboard"
	documentSet.documents = { document }

	local wgdata = SaveToHeaderlessString(documentSet)
	wg.clipboard_set(text, wgdata)
end
