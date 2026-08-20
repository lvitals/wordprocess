--!nonstrict
loadfile("tests/testsuite.lua")()

Cmd.InsertStringIntoParagraph("one two three")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("four")
Cmd.SplitCurrentWord()
Cmd.SetMark()
Cmd.InsertStringIntoParagraph("bold")
Cmd.SetStyle("b")
Cmd.SetMark()
Cmd.InsertStringIntoParagraph("italic")
Cmd.SetStyle("i")
Cmd.SetMark()
Cmd.InsertStringIntoParagraph("underline")
Cmd.SplitCurrentWord()
Cmd.InsertStringIntoParagraph("stillunderline")
Cmd.SetStyle("u")
Cmd.SetStyle("o")
Cmd.InsertStringIntoParagraph("plain")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("heading")
Cmd.ChangeParagraphStyle("H1")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("bullet")
Cmd.ChangeParagraphStyle("LB")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("no bullet")
Cmd.ChangeParagraphStyle("L")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("numbered")
Cmd.ChangeParagraphStyle("LN")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("normal text again")
Cmd.ChangeParagraphStyle("P")

local expected = [[
<html xmlns="http://www.w3.org/1999/xhtml"><head>
<meta http-equiv="Content-Type" content="text/html;charset=utf-8"/>
<meta name="generator" content="WordProcess @@@"/>
<title>main</title>
<style>
@page { size: 21.0cm 29.7cm; margin: 2.5cm 2.5cm 2.5cm 2.5cm; }
body { font-size: 12pt; line-height: 1.15; }
blockquote, .note, .caption { font-size: 10pt; line-height: 1.0; }
blockquote { margin-left: 4.0cm; font-size: 10pt; line-height: 1.0; }
</style>
</head><body>

<p>one two three</p>
<p>four <b>bold</b><i><b>italic</b></i><i><b><u>underline </u></b></i><i><b><u>stillunderline</u></b></i>plain</p>
<h1>heading</h1>
<ul>
<li>bullet</li>
<li style="list-style-type: none;">no bullet</li>
<li style="list-style-type: decimal;" value=1>numbered</li>
</ul>
<p>normal text again</p>
</body>
</html>
]]
expected = expected:gsub("@@@", VERSION)

local output = Cmd.ExportToHTMLString()
AssertEquals(expected, output)
