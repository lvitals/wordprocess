--!nonstrict
loadfile("tests/testsuite.lua")()

local r = Cmd.LoadDocumentSet("testdocs/compatibility-09.wp")
AssertEquals(true, r)

-- A legacy underlined run ending immediately before a space used to emit two
-- closing ODT spans and produce an XML tag mismatch.
local odt = Cmd.ExportToODTString()
local _, opens = odt:gsub("<text:span[%s>]", "")
local _, closes = odt:gsub("</text:span>", "")
AssertEquals(opens, closes)
if odt:find("</text:span><text:s/></text:span>", 1, true) then
	error("ODT export closed an underlined span twice")
end

