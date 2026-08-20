--!nonstrict
loadfile("tests/testsuite.lua")()

GlobalSettings.lookandfeel.denseparagraphs = false
GlobalSettings.lookandfeel.firstlineindent = nil
GlobalSettings.lookandfeel.paragraphspacing = nil
DocumentSet = CreateDocumentSet()
AssertEquals(documentStyles.P.above, 1)
AssertEquals(documentStyles.P.firstindent, 0)

GlobalSettings.lookandfeel.widthmode = "Full width"
GlobalSettings.lookandfeel.maxwidth = 40
AssertEquals(100, GetMaximumAllowedWidth(100))
GlobalSettings.lookandfeel.widthmode = "Column limit"
AssertEquals(40, GetMaximumAllowedWidth(100))
GlobalSettings.lookandfeel.widthmode = "Page preview"
AssertEquals(100, GetMaximumAllowedWidth(100))

GlobalSettings.lookandfeel.denseparagraphs = true
DocumentSet = CreateDocumentSet()
AssertEquals(documentStyles.P.above, 0)
AssertEquals(documentStyles.P.firstindent, 4)

GlobalSettings.lookandfeel.firstlineindent = false
GlobalSettings.lookandfeel.paragraphspacing = false
UpdateDocumentStyles()
AssertEquals(documentStyles.P.above, 0)
AssertEquals(documentStyles.P.firstindent, 0)
