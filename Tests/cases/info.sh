# info verb - page count, JSON validity, encryption reporting.

# Human report shows the page count.
expect_grep "pages: 5" "$PDFUTIL" info "$FIX/text.pdf"

# JSON output is valid and reports the count.
expect_ok      "$PDFUTIL" info --json "$FIX/text.pdf"
"$PDFUTIL" info --json "$FIX/text.pdf" | python3 -m json.tool >/dev/null 2>&1 \
    || fail "info --json is not valid JSON"
expect_grep '"pageCount" : 5' "$PDFUTIL" info --json "$FIX/text.pdf"

# Rotation and text presence surface in the report.
expect_grep "rotation 90" "$PDFUTIL" info "$FIX/rotated.pdf"
expect_grep "no text" "$PDFUTIL" info "$FIX/image.pdf"

# Encrypted document (opened with its password) reports encrypted true.
expect_grep "encrypted: true" "$PDFUTIL" info --password test "$FIX/locked.pdf"

expect_ok "$PDFUTIL" info --help
