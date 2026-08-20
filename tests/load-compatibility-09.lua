--!nonstrict
loadfile("tests/testsuite.lua")()

local r = Cmd.LoadDocumentSet("testdocs/compatibility-09.wp")
AssertEquals(true, r)


