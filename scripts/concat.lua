#!/usr/bin/env -S wp --lua

-- © 2020 David Given.
-- WordProcess is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

-- This user script will concatenate all subdocuments in a file into a single one.
--
-- To use:
--
--     wp --lua concat.lua mynovel.wp output.wp
--
-- (Note the quoting.)
--
-- If mynovel.wp contains subdocuments called Foo, Bar and Baz, this will
-- create a single file called output.wp with the contents of all the
-- subdocuments moved into a new subdocument called 'all'.

-- Main program

local function main(inputfile, outputfile)
	if not outputfile or not inputfile then
		print("Syntax: wp --lua concat.lua <inputfile.wp> <outputfile.wp>")
		os.exit(1)
	end

	print("Loading "..inputfile)
    if not Cmd.LoadDocumentSet(inputfile) then
        print("failed to load document")
        os.exit(1)
    end

	if documentSet:findDocument("all") then
		print("The input file already has a subdocument called 'all'.")
		os.exit(1)
	end

	local docs = { unpack(documentSet:getDocumentList()) }
	local allDoc = documentSet:addDocument(CreateDocument(), "all")
    for _, doc in ipairs(docs) do
		for _, p in ipairs(doc) do
			allDoc[#allDoc+1] = p
		end

		documentSet:deleteDocument(doc.name)
    end

	print("Writing "..outputfile)
	if not Cmd.SaveCurrentDocumentAs(outputfile) then
		print("failed to save new document")
		os.exit(1)
	end
end

main(...)
os.exit(0)

