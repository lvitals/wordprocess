AM_CPPFLAGS = \
	-I$(top_srcdir)/src/c -I$(top_builddir) \
	-isystem $(MINIZIP_HEADER_DIR) $(STB_CFLAGS) \
	$(LUA_CFLAGS) $(CMARK_CFLAGS) $(MINIZIP_CFLAGS) \
	-DFILEFORMAT=8 -DCMARK_STATIC_DEFINE -DWORDPROCESS_STOCK_LUA \
	-DDEFAULT_DICTIONARY_PATH=$(DICTIONARY_PATH) \
	-DDICTIONARY_DIR=$(DICTIONARY_DIR) \
	-DHYPHENATION_DIR=$(HYPHENATION_DIR) \
	-DVERSION=$(APP_VERSION)
AM_CFLAGS = -std=gnu99

bin_PROGRAMS = wp
if BUILD_XWP
bin_PROGRAMS += xwp
endif

common_sources = \
	src/c/globals.h \
	src/c/utils.c src/c/cmark.c src/c/filesystem.c src/c/textbuffer.c \
	src/c/main.c src/c/screen.c src/c/word.c src/c/zip.c \
	src/c/stb_ds_impl.c src/c/lua.c src/c/clipboard.c

wp_SOURCES = $(common_sources) src/c/arch/ncurses/dpy.c
wp_CPPFLAGS = $(AM_CPPFLAGS) $(NCURSESW_CFLAGS) -DFRONTEND=ncurses
wp_LDADD = $(CMARK_LIBS) $(MINIZIP_LIBS) $(LUA_LIBS) $(NCURSESW_LIBS)

if BUILD_XWP
xwp_SOURCES = $(common_sources) \
	src/c/arch/glfw/gui.h \
	src/c/arch/glfw/font.c src/c/arch/glfw/main.c \
	src/c/arch/glfw/utils.c src/c/arch/glfw/stb_impl.c icon.c
xwp_CPPFLAGS = $(AM_CPPFLAGS) $(XWP_CFLAGS) -DFRONTEND=glfw
xwp_LDADD = $(CMARK_LIBS) $(MINIZIP_LIBS) $(LUA_LIBS) $(XWP_LIBS)
endif

noinst_PROGRAMS = multibin2c makeicon update-desktop-caches
multibin2c_SOURCES = tools/multibin2c.c
makeicon_SOURCES = tools/makeicon.c
update_desktop_caches_SOURCES = data/update-desktop-caches.c

lua_sources = \
	src/lua/_prologue.lua src/lua/objects.lua src/lua/events.lua src/lua/margin.lua \
	src/lua/main.lua src/lua/xml.lua src/lua/utils.lua src/lua/scrollbar.lua \
	src/lua/redraw.lua src/lua/settings.lua src/lua/document.lua \
	src/lua/documentset.lua src/lua/paragraph.lua src/lua/forms.lua src/lua/ui.lua \
	src/lua/browser.lua src/lua/html.lua src/lua/xpattern.lua src/lua/fileio.lua \
	src/lua/export.lua src/lua/export/text.lua src/lua/export/html.lua \
	src/lua/export/latex.lua src/lua/export/troff.lua \
	src/lua/export/opendocument.lua src/lua/export/org.lua \
	src/lua/export/markdown.lua src/lua/import.lua src/lua/import/html.lua \
	src/lua/import/text.lua src/lua/import/opendocument.lua \
	src/lua/import/markdown.lua src/lua/import/wordstar.lua src/lua/navigate.lua \
	src/lua/addons/goto.lua src/lua/addons/autosave.lua \
	src/lua/addons/docsetman.lua src/lua/addons/gui.lua \
	src/lua/addons/scrapbook.lua src/lua/addons/statusbar_charstyle.lua \
	src/lua/addons/statusbar_pagecount.lua src/lua/addons/statusbar_position.lua \
	src/lua/addons/statusbar_wordcount.lua src/lua/addons/debug.lua \
	src/lua/addons/look-and-feel.lua src/lua/addons/page-layout.lua \
	src/lua/addons/keymapoverride.lua src/lua/addons/smartquotes.lua \
	src/lua/addons/undo.lua src/lua/addons/spillchocker.lua \
	src/lua/addons/hyphenation.lua src/lua/addons/templates.lua \
	src/lua/addons/directories.lua src/lua/addons/recents.lua \
	src/lua/colours.lua src/lua/menu.lua src/lua/cli.lua

font_sources = \
	data/fonts/FantasqueSansMono-Regular.ttf \
	data/fonts/FantasqueSansMono-Italic.ttf \
	data/fonts/FantasqueSansMono-Bold.ttf \
	data/fonts/FantasqueSansMono-BoldItalic.ttf

BUILT_SOURCES = script_table.h
CLEANFILES = script_table.h font_table.h wordprocess-window-icon.png icon.c wp.1 xwp.1
script_table.h: multibin2c$(EXEEXT) $(lua_sources)
	$(AM_V_GEN)./multibin2c$(EXEEXT) --root '$(abs_top_srcdir)' script_table $(addprefix $(abs_top_srcdir)/,$(lua_sources)) > $@.tmp && mv $@.tmp $@

if BUILD_XWP
BUILT_SOURCES += font_table.h icon.c
font_table.h: multibin2c$(EXEEXT) $(font_sources)
	$(AM_V_GEN)./multibin2c$(EXEEXT) --root '$(abs_top_srcdir)' font_table $(addprefix $(abs_top_srcdir)/,$(font_sources)) > $@.tmp && mv $@.tmp $@
wordprocess-window-icon.png: $(srcdir)/data/icons/wordprocess.svg
	$(AM_V_GEN)$(RSVG_CONVERT) --width 128 --height 128 --output $@ $<
icon.c: makeicon$(EXEEXT) wordprocess-window-icon.png
	$(AM_V_GEN)./makeicon$(EXEEXT) wordprocess-window-icon.png > $@.tmp && mv $@.tmp $@
endif

wp.1: $(srcdir)/wp.man
	$(AM_V_GEN)sed 's/@\{3\}DATE@\{3\}/'"`date '+%-d %B %Y'`"'/g; s/@\{3\}VERSION@\{3\}/$(APP_VERSION)/g' $< > $@
xwp.1: $(srcdir)/xwp.man
	$(AM_V_GEN)sed 's/@\{3\}DATE@\{3\}/'"`date '+%-d %B %Y'`"'/g; s/@\{3\}VERSION@\{3\}/$(APP_VERSION)/g' $< > $@

nodist_man_MANS = wp.1
if BUILD_XWP
nodist_man_MANS += xwp.1
endif

desktopdir = $(datadir)/applications
desktop_DATA = data/wordprocess.desktop
appicondir = $(datadir)/icons/hicolor/scalable/apps
appicon_DATA = data/icons/wordprocess.svg
mimetypeicondir = $(datadir)/icons/hicolor/scalable/mimetypes
mimetypeicon_DATA = application-x-wordprocess.svg
mimedir = $(datadir)/mime/packages
mime_DATA = data/wordprocess.xml

application-x-wordprocess.svg: $(srcdir)/data/icons/wordprocess.svg
	$(AM_V_GEN)cp $< $@
BUILT_SOURCES += application-x-wordprocess.svg
CLEANFILES += application-x-wordprocess.svg

if UPDATE_DESKTOP_CACHES
install-data-hook:
	@test -n "$(DESTDIR)" || \
		./update-desktop-caches$(EXEEXT) "$(DESTDIR)$(datadir)"
endif

DISTCHECK_CONFIGURE_FLAGS = --disable-update-desktop-caches

check_PROGRAMS = ptysmoke
ptysmoke_SOURCES = tests/frontend/ptysmoke.c
ptysmoke_LDADD = -lutil

lua_tests = \
	tests/apply-markup.lua tests/argument-parser.lua \
	tests/change-paragraph-style.lua tests/clipboard.lua \
	tests/compact-keyboard-navigation.lua tests/delete-selection.lua \
	tests/document-round-trip.lua tests/empty-wordcount.lua tests/escape-strings.lua \
	tests/export-to-html.lua tests/export-to-latex.lua tests/export-to-markdown.lua \
	tests/export-to-opendocument.lua tests/export-to-org.lua tests/export-to-text.lua \
	tests/export-to-troff.lua tests/filesystem.lua tests/find-and-replace.lua \
	tests/fixed-mode-click-preserves-viewport.lua tests/get-style-from-word.lua \
	tests/heading-styles.lua tests/hyphenation.lua tests/immutable-paragraphs.lua \
	tests/import-from-html.lua tests/import-from-markdown.lua \
	tests/import-from-opendocument.lua tests/import-from-text.lua \
	tests/import-from-wordstar.lua tests/insert-space-with-style-hint.lua \
	tests/line-boundary-navigation.lua tests/line-down-into-style.lua \
	tests/line-up.lua tests/line-wrapping.lua tests/long-word-wrapping.lua \
	tests/load-compatibility-01.lua tests/load-compatibility-02.lua \
	tests/load-compatibility-03.lua tests/load-compatibility-04.lua \
	tests/load-compatibility-05.lua tests/load-compatibility-06.lua \
	tests/load-compatibility-07.lua tests/load-compatibility-08.lua \
	tests/load-compatibility-09.lua tests/load-compatibility-10-crlf.lua \
	tests/load-failed.lua tests/load-wordgrinder.lua tests/lowlevelclipboard.lua \
	tests/margin-centered-with-width-cap.lua tests/margin-mode-persistence.lua \
	tests/margin-mode-follows-default-on-create.lua tests/move-while-selected.lua \
	tests/numbered-lists.lua tests/page-layout.lua tests/page-navigation.lua \
	tests/parse-string-into-words.lua tests/save-format-escaped-strings.lua \
	tests/scrollbar.lua tests/selection-shortcuts.lua tests/simple-editing.lua \
	tests/smartquotes-selection.lua tests/smartquotes-typing.lua \
	tests/spellchecker.lua tests/tab-insertion.lua tests/tableio.lua \
	tests/textbuffer.lua tests/textbuffer-viewport-follows-backspace.lua \
	tests/type-while-selected.lua tests/undo.lua tests/utf8.lua tests/utils.lua \
	tests/weirdness-cannot-save-settings.lua tests/weirdness-combining-words.lua \
	tests/weirdness-delete-word.lua tests/weirdness-deletion-with-multiple-spaces.lua \
	tests/weirdness-document-rename.lua tests/weirdness-documentset-default-name.lua \
	tests/weirdness-end-of-lines.lua tests/weirdness-forward-delete.lua \
	tests/weirdness-globals-applied-on-startup.lua \
	tests/weirdness-missing-clipboard.lua tests/weirdness-replacing-words.lua \
	tests/weirdness-save-new-document.lua tests/weirdness-splitting-lines-before-space.lua \
	tests/weirdness-stray-control-char-in-export.lua \
	tests/weirdness-style-bleeding-on-deletion.lua \
	tests/weirdness-styled-clipboard.lua tests/weirdness-styling-unicode.lua \
	tests/upgrade-compatibility-clipboard.lua \
	tests/weirdness-word-left-from-end-of-line.lua \
	tests/weirdness-word-left-on-first-word-in-doc.lua \
	tests/weirdness-word-right-to-last-word-in-doc.lua tests/windows-installdir.lua \
	tests/word.lua tests/wrapped-paragraph-scroll-up.lua tests/xpattern.lua
TESTS = $(lua_tests) tests/frontend/wp-pty-smoke.lua
LOG_COMPILER = $(SHELL) $(srcdir)/tests/run-test.sh
AM_TESTS_ENVIRONMENT = \
	WORDPROCESS_TEST_BINARY='$(abs_builddir)/wp'; export WORDPROCESS_TEST_BINARY; \
	WORDPROCESS_PTYSMOKE='$(abs_builddir)/ptysmoke'; export WORDPROCESS_PTYSMOKE; \
	WORDPROCESS_SRCDIR='$(abs_srcdir)'; export WORDPROCESS_SRCDIR;

.PHONY: test valgrind check-valgrind
test: check

valgrind: check-valgrind

check-valgrind: wp
	@$(SHELL) $(srcdir)/tests/valgrind.sh $(abs_builddir)/wp \
		$(addprefix $(abs_srcdir)/,$(lua_tests))

support_files = $(patsubst $(srcdir)/%,%,$(wildcard \
	$(srcdir)/tests/*.lua $(srcdir)/testdocs/* $(srcdir)/scripts/*.lua \
	$(srcdir)/docs/*.md $(srcdir)/licenses/* $(srcdir)/man/*.1))
EXTRA_DIST = $(lua_sources) $(font_sources) $(TESTS) $(support_files) \
	tests/run-test.sh wp.man xwp.man NOTICE data/wordprocess.xml \
	data/wordprocess.desktop data/icons/wordprocess.svg \
	data/american-canadian.dictionary data/british.dictionary
