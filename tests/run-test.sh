#!/bin/sh
set -eu

test_file=$1
case "$test_file" in
  /*) test_path=$test_file ;;
  *)
    test_dir=$(dirname "$test_file")
    test_name=$(basename "$test_file")
    test_path=$(CDPATH= cd "$test_dir" && pwd)/$test_name
    ;;
esac

cd "$WORDPROCESS_SRCDIR"
case "$test_file" in
  */frontend/wp-pty-smoke.lua)
    exec "$WORDPROCESS_TEST_BINARY" --lua "$test_path" \
      "$WORDPROCESS_TEST_BINARY" "$WORDPROCESS_PTYSMOKE"
    ;;
  *) exec "$WORDPROCESS_TEST_BINARY" --lua "$test_path" ;;
esac
