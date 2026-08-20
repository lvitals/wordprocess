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
