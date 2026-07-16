# merge verb - concatenation, per-input ranges, overwrite policy.

# text.pdf (5) + outline.pdf (5) = 10 pages.
expect_ok "$PDFUTIL" merge -o "$TMP/merged.pdf" "$FIX/text.pdf" "$FIX/outline.pdf"
expect_grep "pages: 10" "$PDFUTIL" info "$TMP/merged.pdf"

# A -p range binds to the preceding input: 2 + 5 = 7 pages.
expect_ok "$PDFUTIL" merge -o "$TMP/merged7.pdf" "$FIX/text.pdf" -p 1-2 "$FIX/outline.pdf"
expect_grep "pages: 7" "$PDFUTIL" info "$TMP/merged7.pdf"

# Overwrite policy: existing output refused without --force, allowed with it.
expect_fail "$PDFUTIL" merge -o "$TMP/merged.pdf" "$FIX/text.pdf" "$FIX/outline.pdf"
expect_ok   "$PDFUTIL" merge -o "$TMP/merged.pdf" --force "$FIX/text.pdf" "$FIX/outline.pdf"

# Missing -o and single input without a range are usage errors.
expect_code 1 "$PDFUTIL" merge "$FIX/text.pdf" "$FIX/outline.pdf"
expect_code 1 "$PDFUTIL" merge -o "$TMP/x.pdf" "$FIX/text.pdf"

expect_ok "$PDFUTIL" merge --help
