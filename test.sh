#!/bin/sh
# test.sh - build pdfutil, (re)generate fixtures if missing, and run the smoke
# tests in Tests/cases/*.sh. Every case file is sourced with access to the
# helpers and the $PDFUTIL / $FIX / $TMP variables defined below.

set -e

cd "$(dirname "$0")"

./build.sh

FIX="Tests/fixtures"
TMP="Tests/tmp"
PDFUTIL="./pdfutil"

if [ ! -d "$FIX" ]; then
    echo "Generating fixtures..."
    mkdir -p "$FIX"
    swift Tests/make-fixtures.swift "$FIX"
fi

rm -rf "$TMP"
mkdir -p "$TMP"

FAILURES=0
fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }

# Assertion helpers. All wrap the command in an `if`, so a failing command never
# trips `set -e`; failures are counted and reported at the end.
expect_ok()   { if ! "$@" >/dev/null 2>&1; then fail "expected success: $*"; fi; }
expect_fail() { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }
expect_code() {
    want="$1"; shift
    if "$@" >/dev/null 2>&1; then got=0; else got=$?; fi
    if [ "$got" != "$want" ]; then fail "expected exit $want, got $got: $*"; fi
}
expect_grep() {
    pat="$1"; shift
    if ! "$@" 2>/dev/null | grep -q -- "$pat"; then fail "expected /$pat/ from: $*"; fi
}
expect_nogrep() {
    pat="$1"; shift
    if "$@" 2>/dev/null | grep -q -- "$pat"; then fail "unexpected /$pat/ from: $*"; fi
}

for casefile in Tests/cases/*.sh; do
    echo "== $casefile =="
    . "$casefile"
done

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES test(s) failed." >&2
    exit 1
fi
echo "All tests passed."
