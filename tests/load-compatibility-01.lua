--!nonstrict
loadfile("tests/testsuite.lua")()

local r = Cmd.LoadDocumentSet("testdocs/compatibility-01.wp")
AssertEquals(true, r)

