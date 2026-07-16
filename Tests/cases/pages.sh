# pages verb - extract/reorder, delete, ranges, overwrite policy.
# This case file also exercises the PageRange grammar through the CLI.

# Extract in reverse order: first output page is the old page 5.
expect_ok "$PDFUTIL" pages --extract 5-1 -o "$TMP/rev.pdf" "$FIX/text.pdf"
expect_grep "pages: 5" "$PDFUTIL" info "$TMP/rev.pdf"
expect_grep "PAGE-5-MARKER" "$PDFUTIL" text -p 1 "$TMP/rev.pdf"

# Reorder/duplicate with an explicit list.
expect_ok "$PDFUTIL" pages --extract 3,1,3 -o "$TMP/dup.pdf" "$FIX/text.pdf"
expect_grep "pages: 3" "$PDFUTIL" info "$TMP/dup.pdf"
expect_grep "PAGE-3-MARKER" "$PDFUTIL" text -p 1 "$TMP/dup.pdf"

# Delete a range: 5 - 3 = 2 pages remain.
expect_ok "$PDFUTIL" pages --delete 2-4 -o "$TMP/del.pdf" "$FIX/text.pdf"
expect_grep "pages: 2" "$PDFUTIL" info "$TMP/del.pdf"

# Page-range grammar errors are usage errors (exit 1).
expect_code 1 "$PDFUTIL" pages --extract 9 "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" pages --extract 0 "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" pages --extract 1-x "$FIX/text.pdf"

# Exactly one mode flag is required.
expect_code 1 "$PDFUTIL" pages "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" pages --extract 1 --delete 2 "$FIX/text.pdf"

# Overwrite policy.
expect_fail "$PDFUTIL" pages --extract 1 -o "$TMP/rev.pdf" "$FIX/text.pdf"
expect_ok   "$PDFUTIL" pages --extract 1 -o "$TMP/rev.pdf" --force "$FIX/text.pdf"

expect_ok "$PDFUTIL" pages --help
