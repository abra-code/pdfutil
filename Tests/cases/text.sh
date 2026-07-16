# text verb - extraction, page ranges, password handling, no-text-layer failure.

# Full-document extraction includes every page's marker.
expect_grep "PAGE-3-MARKER" "$PDFUTIL" text "$FIX/text.pdf"

# A page range selects only the requested page.
expect_grep   "PAGE-2-MARKER" "$PDFUTIL" text -p 2 "$FIX/text.pdf"
expect_nogrep "PAGE-1-MARKER" "$PDFUTIL" text -p 2 "$FIX/text.pdf"

# Locked PDF: fails with no password, succeeds with the right one.
expect_fail "$PDFUTIL" text "$FIX/locked.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text --password test "$FIX/locked.pdf"

# Image-only PDF has no text layer -> processing error (exit 2).
expect_code 2 "$PDFUTIL" text "$FIX/image.pdf"

# Help exits 0, both globally and for the verb.
expect_ok "$PDFUTIL" --help
expect_ok "$PDFUTIL" text --help

# -o writes to a file under the overwrite policy.
expect_ok "$PDFUTIL" text -o "$TMP/text-out.txt" "$FIX/text.pdf"
expect_grep "PAGE-4-MARKER" cat "$TMP/text-out.txt"
expect_fail "$PDFUTIL" text -o "$TMP/text-out.txt" "$FIX/text.pdf"
expect_ok "$PDFUTIL" text -o "$TMP/text-out.txt" --force "$FIX/text.pdf"
