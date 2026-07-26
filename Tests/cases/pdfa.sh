# pdfa verb - rewrite as PDF/A (PDF/A-2B via Apple's writer).

# Round-trips the document: page count and text layer are preserved.
expect_ok "$PDFUTIL" pdfa -o "$TMP/a.pdf" "$FIX/text.pdf"
expect_grep "pages: 5" "$PDFUTIL" info "$TMP/a.pdf"
expect_grep "needle" "$PDFUTIL" text -p 3 "$TMP/a.pdf"

# qpdf: decompressed, the output carries the PDF/A XMP marker (pdfaid).
if [ -x "$QPDF" ]; then
    "$QPDF" --qdf --object-streams=disable "$TMP/a.pdf" "$TMP/a-qdf.pdf" 2>/dev/null
    grep -a -q "pdfaid" "$TMP/a-qdf.pdf" || fail "pdfa output lacks a PDF/A (pdfaid) marker"
fi

# Overwrite policy.
expect_fail "$PDFUTIL" pdfa -o "$TMP/a.pdf" "$FIX/text.pdf"
expect_ok   "$PDFUTIL" pdfa -o "$TMP/a.pdf" --force "$FIX/text.pdf"

expect_ok "$PDFUTIL" pdfa --help
