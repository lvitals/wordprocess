--!nonstrict
loadfile("tests/testsuite.lua")()

local control = string.char
local paragraphStyleBlock = control(0x1d, 0x02, 0x00, 0x11, 0x05)
local source = table.concat({
	".pa\r\n",
	paragraphStyleBlock, "Migrated title\r\n",
	"Plain ", control(0x02), "bold", control(0x02), " ",
	control(0x19), "italic", control(0x19), " ",
	control(0x13), "underlined", control(0x13), " text",
	control(0x8d), "continues ", "soft", control(0x1e),
	control(0x8d), "wrap active", control(0x1f), control(0x8d), "hyphen\r\n",
	control(0xc1), " parity\r\n",
	control(0x1b, 0x82), " accent\r\n",
	control(0x1a), "ignored",
})

local document = Cmd.ImportWordStarString(source)
AssertEquals(4, #document)
AssertEquals("H1", document[1].style)
AssertEquals("Migrated title", document[1]:asString())
AssertEquals("Plain bold italic underlined text continues softwrap active-hyphen",
	document[2]:asString())
AssertEquals("A parity", document[3]:asString())
AssertEquals("é accent", document[4]:asString())
AssertEquals(true, bit32.btest(wg.getstylefromword(document[2][2], 2), wg.BOLD))
AssertEquals(true, bit32.btest(wg.getstylefromword(document[2][3], 2), wg.ITALIC))
AssertEquals(true, bit32.btest(wg.getstylefromword(document[2][4], 2), wg.UNDERLINE))

local before = #documentSet.documents
AssertEquals(true, Cmd.ImportWordStarFile("testdocs/wordstar-example.ws"))
AssertEquals(before + 1, #documentSet.documents)
