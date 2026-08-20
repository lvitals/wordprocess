--!nonstrict
loadfile("tests/testsuite.lua")()

local r = Cmd.LoadDocumentSet("testdocs/compatibility-05.wp")
AssertEquals(true, r)


