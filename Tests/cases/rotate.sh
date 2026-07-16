# rotate verb - additive rotation, page ranges, in-place default, validation.

# Rotate all pages 90; info reports rotation 90.
expect_ok "$PDFUTIL" rotate 90 -o "$TMP/rot90.pdf" "$FIX/text.pdf"
expect_grep "rotation 90" "$PDFUTIL" info "$TMP/rot90.pdf"

# Rotation is additive: 90 again -> 180 (edit in place this time).
cp "$TMP/rot90.pdf" "$TMP/rot180.pdf"
expect_ok "$PDFUTIL" rotate 90 "$TMP/rot180.pdf"
expect_grep "rotation 180" "$PDFUTIL" info "$TMP/rot180.pdf"

# Negative angle is accepted.
expect_ok "$PDFUTIL" rotate -90 -o "$TMP/rotneg.pdf" "$FIX/text.pdf"
expect_grep "rotation 270" "$PDFUTIL" info "$TMP/rotneg.pdf"

# A page range limits the rotation.
expect_ok "$PDFUTIL" rotate 90 -p 2 -o "$TMP/rotp.pdf" "$FIX/text.pdf"
expect_grep "page 2: 612x792 pt, rotation 90" "$PDFUTIL" info "$TMP/rotp.pdf"
expect_nogrep "page 1: 612x792 pt, rotation" "$PDFUTIL" info "$TMP/rotp.pdf"

# Invalid angle and missing args are usage errors.
expect_code 1 "$PDFUTIL" rotate 45 -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" rotate 90

expect_ok "$PDFUTIL" rotate --help
