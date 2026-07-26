#!/bin/sh
# test.sh - build pdfutil, (re)generate fixtures if missing, and run the smoke
# tests in Tests/cases/*.sh. Every case file is sourced with access to the
# helpers and the $PDFUTIL / $FIX / $TMP variables defined below.

set -e

cd "$(dirname "$0")"

./build.sh

FIX="Tests/fixtures"
TMP="Tests/tmp"
PDFUTIL="./build/pdfutil"

# qpdf is an optional external cross-checker. The encrypt, flatten, linearize, and
# pdfa cases use it as an independent parser to confirm pdfutil's output, since a
# check that only asks PDFKit about a file PDFKit wrote proves little.
#
# These are deliberately shallow smoke checks. The thorough cross-tool tests live
# in the QuickPDFApp repo, which embeds both qpdf and pdfutil and is the right
# place to compare the two against each other.
#
# Resolution order (a relative peer path only - never an absolute one, this repo
# is public):
#   1. $QPDF from the environment
#   2. a QuickPDFApp checkout sitting next to this one
#   3. qpdf on $PATH
QPDF_PEER="../QuickPDFApp/QuickPDF.app/Contents/Helpers/qpdf"
if [ -z "${QPDF:-}" ] && [ -x "$QPDF_PEER" ]; then
    QPDF="$QPDF_PEER"
fi
if [ -z "${QPDF:-}" ]; then
    QPDF="$(command -v qpdf 2>/dev/null || true)"
fi
if [ -x "${QPDF:-}" ]; then
    echo "qpdf cross-checks: $QPDF ($("$QPDF" --version 2>/dev/null | head -1))"
else
    # Warn rather than fail: qpdf is a cross-checker, not a dependency. The warning
    # matters because a silent skip reads as "verified" when nothing was verified.
    QPDF=""
    echo "WARNING: qpdf not found - skipping all qpdf cross-checks."
    echo "         Expected a QuickPDFApp checkout next to this repo at"
    echo "         $QPDF_PEER, or qpdf on \$PATH, or QPDF=/path/to/qpdf."
fi

if [ ! -d "$FIX" ]; then
    echo "Generating fixtures..."
    mkdir -p "$FIX"
    swift Tests/make-fixtures.swift "$FIX"
fi

rm -rf "$TMP"
mkdir -p "$TMP"

# Failure counter. Cases may run an assertion inside a pipeline (the password-on-
# stdin tests do), and a pipeline stage is a subshell whose variable updates are
# lost to the parent. Count failures in a file so those still register; the
# message itself has already gone to stderr, so one line per failure is enough.
FAILLOG="$TMP/.failures"
: > "$FAILLOG"
fail() { echo "FAIL: $*" >&2; echo x >> "$FAILLOG"; }

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

FAILURES=$(wc -l < "$FAILLOG" | tr -d ' ')
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES test(s) failed." >&2
    exit 1
fi
echo "All tests passed."
