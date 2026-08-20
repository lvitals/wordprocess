--!nonstrict
loadfile("tests/testsuite.lua")()

local r = Cmd.LoadDocumentSet("testdocs/compatibility-04.wp")
AssertEquals(true, r)


