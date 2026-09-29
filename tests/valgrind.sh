#!/bin/sh
# Runs the full test suite through valgrind's memcheck, reusing the exact
# same tests and binary as `make check` (the ncurses
# build - config.py always points TEST_BINARY at it on non-Windows).
#
# Usage: tests/valgrind.sh [path-to-wp-binary] [test.lua ...]
# Defaults to the Autotools build output if no binary is given. Run from the
# repository root (test scripts resolve paths like "testdocs/..." relative
# to cwd).

set -e

VALGRIND_TIMEOUT=${VALGRIND_TIMEOUT:-60}

BINARY="${1:-./wp}"
if [ "$#" -gt 0 ]; then
    shift
fi

if [ ! -x "$BINARY" ]; then
    echo "error: '$BINARY' not found or not executable" >&2
    echo "build it first (make), or pass a binary path" >&2
    exit 1
fi

preflight_log=$(mktemp)
if ! valgrind --tool=memcheck --quiet true >"$preflight_log" 2>&1; then
    echo "error: Valgrind cannot start on this system" >&2
    cat "$preflight_log" >&2
    rm -f "$preflight_log"
    exit 1
fi
rm -f "$preflight_log"

TESTS="apply-markup argument-parser change-paragraph-style clipboard
delete-selection escape-strings export-to-html export-to-latex
export-to-markdown export-to-opendocument export-to-org export-to-text
export-to-troff filesystem find-and-replace fixed-mode-click-preserves-viewport
get-style-from-word
heading-styles immutable-paragraphs import-from-html import-from-markdown
import-from-opendocument import-from-text insert-space-with-style-hint
line-boundary-navigation line-down-into-style line-up line-wrapping
load-0.1 load-0.2 load-0.3.3 load-0.4.1 load-0.5.3 load-0.6 load-0.6-v6
load-0.7.2 load-0.8.crlf load-0.8 load-failed lowlevelclipboard
margin-mode-persistence move-while-selected numbered-lists parse-string-into-words
save-format-escaped-strings scrollbar simple-editing smartquotes-selection
smartquotes-typing spellchecker tableio type-while-selected undo utf8
utils weirdness-cannot-save-settings weirdness-combining-words
weirdness-delete-word weirdness-deletion-with-multiple-spaces
weirdness-document-rename weirdness-documentset-default-name
weirdness-end-of-lines weirdness-forward-delete
weirdness-globals-applied-on-startup weirdness-missing-clipboard
weirdness-replacing-words weirdness-save-new-document
weirdness-splitting-lines-before-space weirdness-stray-control-char-in-export
weirdness-style-bleeding-on-deletion weirdness-styled-clipboard
weirdness-styling-unicode weirdness-upgrade-0.6-with-clipboard
weirdness-word-left-from-end-of-line weirdness-word-left-on-first-word-in-doc
weirdness-word-right-to-last-word-in-doc windows-installdir word xpattern"

# Automake passes its authoritative test list. The built-in list above remains
# available for invoking this script directly from the source tree.
if [ "$#" -gt 0 ]; then
    TESTS="$*"
fi

fail=0
total=0
for t in $TESTS; do
    total=$((total + 1))
    log=$(mktemp)
    case "$t" in
        *.lua) test_path=$t; test_name=$(basename "$t" .lua) ;;
        *) test_path="tests/$t.lua"; test_name=$t ;;
    esac
    printf 'RUN   %s\n' "$test_name"
    if timeout "$VALGRIND_TIMEOUT" valgrind \
        --leak-check=full \
        --show-leak-kinds=all \
        --track-origins=yes \
        --error-exitcode=99 \
        --quiet \
        "$BINARY" --lua "$test_path" >"$log" 2>&1
    then
        echo "PASS  $test_name"
    else
        status=$?
        if [ "$status" -eq 124 ]; then
            echo "TIMEOUT  $test_name (${VALGRIND_TIMEOUT}s)"
        else
            echo "FAIL  $test_name"
        fi
        cat "$log"
        fail=$((fail + 1))
    fi
    rm -f "$log"
done

echo
echo "$((total - fail))/$total clean, $fail with errors or leaks"
[ "$fail" -eq 0 ]
