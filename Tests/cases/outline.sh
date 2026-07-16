# outline verb - chapter listing, page destinations, absence handling.

# outline.pdf has three chapters at pages 1, 3, 5.
expect_grep "Chapter 1" "$PDFUTIL" outline "$FIX/outline.pdf"
expect_grep "Chapter 3  p5" "$PDFUTIL" outline "$FIX/outline.pdf"

# JSON output is valid and nested.
"$PDFUTIL" outline --json "$FIX/outline.pdf" | python3 -m json.tool >/dev/null 2>&1 \
    || fail "outline --json is not valid JSON"
expect_grep '"label" : "Chapter 2"' "$PDFUTIL" outline --json "$FIX/outline.pdf"

# A document with no outline notes the absence on stderr and exits 0.
expect_ok "$PDFUTIL" outline "$FIX/text.pdf"
"$PDFUTIL" outline "$FIX/text.pdf" 2>&1 >/dev/null | grep -q "no outline" \
    || fail "outline on text.pdf did not note the absence"

expect_ok "$PDFUTIL" outline --help
