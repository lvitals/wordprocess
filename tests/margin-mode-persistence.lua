--!nonstrict
loadfile("tests/testsuite.lua")()

-- Regression test for a bug where the paragraph-number margin controller
-- (src/lua/margin.lua) registers a single module-level "Changed" listener
-- that is never scoped to a particular document. Left unguarded, it kept
-- firing for whatever document happened to be current and stomped on its
-- margin/viewmode -- leaking a stale margin onto a freshly switched-to
-- document (a visible gutter with no numbers in it), and silently
-- reverting "hide margin" on the very next edit.

local docAname = currentDocument.name

SetMarginMode(3) -- paragraph numbers
AssertEquals(3, currentDocument.viewmode)
if currentDocument.margin <= 0 then
	error("expected margin mode 3 to reserve a nonzero margin width")
end

-- Switching to a fresh document must not inherit docA's margin/viewmode,
-- neither immediately nor after the next "Changed" event (which is what
-- the leaked listener reacts to).
local docB = CreateDocument()
documentSet:addDocument(docB, "docB")
documentSet:setCurrent("docB")

AssertEquals(1, currentDocument.viewmode)
AssertEquals(0, currentDocument.margin)

FireEvent("Changed")
AssertEquals(1, currentDocument.viewmode)
AssertEquals(0, currentDocument.margin)

-- Back on docA: turning the margin off must stick even after further
-- edits fire more "Changed" events.
documentSet:setCurrent(docAname)
AssertEquals(3, currentDocument.viewmode)

SetMarginMode(1) -- hide
AssertEquals(1, currentDocument.viewmode)
AssertEquals(0, currentDocument.margin)

FireEvent("Changed")
AssertEquals(1, currentDocument.viewmode)
AssertEquals(0, currentDocument.margin)

-- Regression: a document loaded from a file that saved viewmode == 3 from
-- a *previous* session never runs paragraph_number_controller.attach() in
-- this one (that only happens when the user explicitly picks the mode
-- from the menu), so its self.token is nil. detach() used to unconditionally
-- assert(self.token), so "Hide margin" on such a document errored out
-- before ever reaching currentDocument.viewmode = mode -- the margin
-- silently stayed on.
local docC = CreateDocument()
docC.viewmode = 3
docC.margin = 2
documentSet:addDocument(docC, "docC")
documentSet:setCurrent("docC")

SetMarginMode(1) -- hide, must not error and must actually take effect
AssertEquals(1, currentDocument.viewmode)
AssertEquals(0, currentDocument.margin)
