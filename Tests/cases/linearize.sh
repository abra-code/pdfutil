# linearize verb - rewrite in linearized ("fast web view") form.

QPDF="/Users/tkukielk/Development/QuickPDFApp/QuickPDF.app/Contents/Helpers/qpdf"

# Round-trips the document: page count and text layer are preserved.
expect_ok "$PDFUTIL" linearize -o "$TMP/lin.pdf" "$FIX/text.pdf"
expect_grep "pages: 5" "$PDFUTIL" info "$TMP/lin.pdf"
expect_grep "needle" "$PDFUTIL" text -p 3 "$TMP/lin.pdf"

# qpdf confirms the output is linearized and the plain input is not.
if [ -x "$QPDF" ]; then
    "$QPDF" --check "$TMP/lin.pdf" 2>/dev/null | grep -qi "is linearized" \
        || fail "linearize output is not linearized"
    "$QPDF" --check "$FIX/text.pdf" 2>/dev/null | grep -qi "not linearized" \
        || fail "plain text.pdf unexpectedly reports linearized"
fi

# Overwrite policy.
expect_fail "$PDFUTIL" linearize -o "$TMP/lin.pdf" "$FIX/text.pdf"
expect_ok   "$PDFUTIL" linearize -o "$TMP/lin.pdf" --force "$FIX/text.pdf"

expect_ok "$PDFUTIL" linearize --help
