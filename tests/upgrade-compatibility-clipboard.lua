--!nonstrict
loadfile("tests/testsuite.lua")()

AssertEquals(Cmd.LoadDocumentSet("testdocs/compatibility-clipboard.wp"), true)
local filename = wg.mkdtemp().."/tempfile"
AssertEquals(Cmd.SaveCurrentDocumentAs(filename), true)
