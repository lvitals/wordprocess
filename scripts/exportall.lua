#!/usr/bin/env -S wp --lua

-- © 2013 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

-- This user script will export all subdocuments in a document set.
--
-- To use:
--
--     wp --lua exportall.lua mynovel.wp output.html
--
-- (Note the quoting.)
--
-- If mynovel.wp contains subdocuments called Foo, Bar and Baz, this will
-- create files output.1.Foo.html, output.2.Bar.html and output.3.Baz.html.

-- Main program

local function main(inputfile, template)
	if not template then
		print("Syntax: wp --lua exportall.lua '<inputfile.wp> <outputfiletemplate>'")
		os.exit(1)
	end

    local export_table =
    {
        ["wp"] = Cmd.SaveCurrentDocumentAs,
        ["odt"] = Cmd.ExportODTFile,
        ["html"] = Cmd.ExportHTMLFile,
        ["tr"] = Cmd.ExportTroffFile,
        ["tex"] = Cmd.ExportLatexFile, 
        ["txt"] = Cmd.ExportTextFile,
		["md"] = Cmd.ExportMarkdownFile,
    }
    local _, _, extension = template:find("%.(%w+)$")
    local exporter = export_table[extension or ""]
    if not exporter then
        print("Unknown output format")
        os.exit(1)
    end

    if not Cmd.LoadDocumentSet(inputfile) then
        print("failed to load document")
        os.exit(1)
    end

    for i, doc in ipairs(documentSet:getDocumentList()) do
        local outputfile = template:gsub("%.(%w+)$", "."..i.."."..doc.name..".%1")
        Document = doc
        if not exporter(outputfile) then
            print("failed to write output file")
            os.exit(1)
        end
    end
end

main(...)
os.exit(0)

