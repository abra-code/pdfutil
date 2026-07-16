# split verb - by page count and by chapters.

# --every 2 on a 5-page doc yields 3 files of 2/2/1 pages.
expect_ok "$PDFUTIL" split --every 2 -o "$TMP/every" "$FIX/text.pdf"
[ -f "$TMP/every-001.pdf" ] && [ -f "$TMP/every-002.pdf" ] && [ -f "$TMP/every-003.pdf" ] \
    || fail "split --every did not produce three files"
[ -f "$TMP/every-004.pdf" ] && fail "split --every produced a fourth file"
expect_grep "pages: 2" "$PDFUTIL" info "$TMP/every-001.pdf"
expect_grep "pages: 1" "$PDFUTIL" info "$TMP/every-003.pdf"

# --chapters on outline.pdf (chapters at pages 1,3,5) yields 2/2/1.
expect_ok "$PDFUTIL" split --chapters -o "$TMP/chap" "$FIX/outline.pdf"
[ -f "$TMP/chap-001.pdf" ] && [ -f "$TMP/chap-002.pdf" ] && [ -f "$TMP/chap-003.pdf" ] \
    || fail "split --chapters did not produce three files"
expect_grep "pages: 2" "$PDFUTIL" info "$TMP/chap-001.pdf"
expect_grep "pages: 1" "$PDFUTIL" info "$TMP/chap-003.pdf"

# --chapters on a doc without an outline is a processing error.
expect_code 2 "$PDFUTIL" split --chapters -o "$TMP/none" "$FIX/text.pdf"

# --every and --chapters together is a usage error.
expect_code 1 "$PDFUTIL" split --every 2 --chapters "$FIX/outline.pdf"

# Pre-flight: a pre-existing target name aborts before writing any part.
rm -f "$TMP/pf-001.pdf" "$TMP/pf-002.pdf" "$TMP/pf-003.pdf"
: > "$TMP/pf-002.pdf"
expect_code 2 "$PDFUTIL" split --every 2 -o "$TMP/pf" "$FIX/text.pdf"
if [ -f "$TMP/pf-001.pdf" ]; then fail "split pre-flight wrote part 1 despite a later collision"; fi

expect_ok "$PDFUTIL" split --help
