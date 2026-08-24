--!nonstrict
loadfile("tests/testsuite.lua")()

AssertEquals(true, Cmd.LoadDocumentSet("testdocs/wordgrinder-example.wg"))
AssertEquals("Migrated document", currentDocument.name)
AssertEquals("This document was created by WordGrinder.",
	currentDocument[1]:asString())

-- The WordGrinder signatures select the same proven v1/v2/v3 decoders used by
-- equivalent WordProcess documents.
for _, filename in ipairs({
	"testdocs/compatibility-01.wp",
	"testdocs/compatibility-04.wp",
	"testdocs/compatibility-07.wp",
}) do
	local data = assert(wg.readfile(filename))
	data = data:gsub("^WordProcess dumpfile", "WordGrinder dumpfile", 1)
	local loaded = LoadFromString(filename:gsub("%.wp$", ".wg"), data)
	AssertNotNull(loaded)
	AssertEquals(true, #loaded.documents > 0)
end
