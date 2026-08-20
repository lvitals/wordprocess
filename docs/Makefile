MAN_DIR = ../man
MAN_PAGES = $(wildcard $(MAN_DIR)/*.[1-9])
MD_FILES = $(notdir $(addsuffix .md,$(MAN_PAGES)))
HTML_FILES = $(notdir $(addsuffix .html,$(MAN_PAGES)))

all: man-md man-html

man-md: $(MD_FILES)

%.md: $(MAN_DIR)/%
	mandoc -Tmarkdown $< > $@

man-html: $(HTML_FILES)

%.html: $(MAN_DIR)/%
	mandoc -Thtml $< > $@

clean:
	rm -f $(MD_FILES) $(HTML_FILES)

.PHONY: all man-md man-html clean
