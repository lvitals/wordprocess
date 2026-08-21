--!nonstrict
loadfile("tests/testsuite.lua")()

local layout = ApplyPageLayoutProfile(currentDocument, "ABNT")
AssertEquals(21.0, layout.pageWidthCm)
AssertEquals(29.7, layout.pageHeightCm)
AssertEquals(3.0, layout.marginTopCm)
AssertEquals(3.0, layout.marginLeftCm)
AssertEquals(2.0, layout.marginRightCm)
AssertEquals(2.0, layout.marginBottomCm)
AssertEquals(1.5, layout.lineSpacing)
AssertEquals(10, layout.specialFontSizePt)
AssertEquals(1.0, layout.specialLineSpacing)
AssertEquals(76, GetDocumentTextWidthColumns(currentDocument))
AssertEquals(2, GetDocumentLineHeightRows(currentDocument, "P"))
AssertEquals(1, GetDocumentLineHeightRows(currentDocument, "Q"))

-- Page layout controls vertical editor spacing without changing the separate
-- first-line indentation preference.
GlobalSettings.lookandfeel.firstlineindent = false
UpdateDocumentStyles()
AssertEquals(0, documentStyles.P.firstindent)
AssertEquals(2, GetDocumentLineHeightRows(currentDocument, "P"))

local latex = Cmd.ExportToLatexString()
if not latex:find("paperwidth=21.0cm,paperheight=29.7cm", 1, true) then
	error("LaTeX export did not receive ABNT paper dimensions")
end
if not latex:find("top=3.0cm,right=2.0cm,bottom=2.0cm,left=3.0cm", 1, true) then
	error("LaTeX export did not receive ABNT margins")
end
if not latex:find("\\setstretch{1.5}", 1, true) then
	error("LaTeX export did not receive ABNT line spacing")
end

local html = Cmd.ExportToHTMLString()
if not html:find("@page { size: 21.0cm 29.7cm", 1, true) then
	error("HTML export did not receive ABNT paper dimensions")
end

ApplyPageLayoutProfile(currentDocument, "Book")
AssertEquals(14.0, currentDocument.pageLayout.pageWidthCm)
AssertEquals(21.0, currentDocument.pageLayout.pageHeightCm)
AssertEquals(54, GetDocumentTextWidthColumns(currentDocument))

-- Paragraph/style position and physical pages are deliberately independent.
local short = CreateDocument()
short[1] = CreateParagraph("H1", {"one"})
for i = 2, 10 do
	short[i] = CreateParagraph(i == 8 and "H2" or "P", {"short"})
end
currentDocument = short
documentSet.current = short
short:renumber()
AssertEquals(10, #short)
AssertEquals(1, short:getPageCount())
local function statusText()
	local terms = {}
	FireEvent("BuildStatusBar", terms)
	local values = {}
	for _, term in ipairs(terms) do values[#values+1] = term.value end
	return table.concat(values, " | ")
end
short.cp = 1
short[1].style = "P"
AssertEquals(true, statusText():find("P: 1/10", 1, true) ~= nil)
AssertEquals(true, statusText():find("Pg: 1/1", 1, true) ~= nil)
short[1].style = "H1"
AssertEquals(true, statusText():find("H1: 1/10", 1, true) ~= nil)
AssertEquals(true, statusText():find("Pg: 1/1", 1, true) ~= nil)
short.cp = 8
AssertEquals(true, statusText():find("H2: 8/10", 1, true) ~= nil)
AssertEquals(true, statusText():find("Pg: 1/1", 1, true) ~= nil)
short.cp = 2
AssertEquals(true, statusText():find("P: 2/10", 1, true) ~= nil)
AssertEquals(true, statusText():find("Pg: 1/1", 1, true) ~= nil)
short[3].style, short.cp = "H3", 3
AssertEquals(true, statusText():find("H3: 3/10", 1, true) ~= nil)
AssertEquals(true, statusText():find("Pg: 1/1", 1, true) ~= nil)
short[4].style, short.cp = "H4", 4
AssertEquals(true, statusText():find("H4: 4/10", 1, true) ~= nil)
AssertEquals(true, statusText():find("Pg: 1/1", 1, true) ~= nil)

-- A single paragraph can cross several physical pages without changing P:.
local long = CreateDocument()
local words = {}
for i = 1, 5000 do words[i] = "word" end
long[1] = CreateParagraph("P", words)
currentDocument = long
documentSet.current = long
long:renumber()
local tallPages = long:getPageCount()
AssertEquals(true, tallPages > 3)
local thirdPage = assert(long:getPositionForPage(3))
AssertEquals(1, thirdPage.p)
AssertEquals(true, long:gotoNavigationPosition(thirdPage))
AssertEquals(1, long.cp)
AssertEquals(3, long:getPageAtPosition())
AssertEquals(true, statusText():find("P: 1/1", 1, true) ~= nil)
AssertEquals(true, statusText():find("Pg: 3/", 1, true) ~= nil)

-- Only layout changes: paragraph total is stable while pagination changes.
local originalPages = long:getPageCount()
long.pageLayout.pageHeightCm = 15
long._pageIndex = nil
AssertEquals(1, #long)
AssertEquals(true, long:getPageCount() > originalPages)
local heightPages = long:getPageCount()
long.pageLayout.marginLeftCm = 6
long.pageLayout.marginRightCm = 6
long._pageIndex = nil
AssertEquals(1, #long)
AssertEquals(true, long:getPageCount() > heightPages)
local marginPages = long:getPageCount()
long.pageLayout.fontSizePt = 20
long._pageIndex = nil
AssertEquals(1, #long)
AssertEquals(true, long:getPageCount() > marginPages)
