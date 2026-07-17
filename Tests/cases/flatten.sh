# flatten verb - burn a filled form's values into the page content.

QPDF="/Users/tkukielk/Development/QuickPDFApp/QuickPDF.app/Contents/Helpers/qpdf"

# Before flattening, the "Alice" value lives in the widget, not the page text.
expect_nogrep "Alice" "$PDFUTIL" text "$FIX/form-filled.pdf"

# After flattening, the value is painted into the page and extractable as text.
expect_ok "$PDFUTIL" flatten -o "$TMP/flat.pdf" "$FIX/form-filled.pdf"
expect_grep "Alice" "$PDFUTIL" text "$TMP/flat.pdf"

# The interactive widget is gone (guarded on qpdf's presence).
if [ -x "$QPDF" ]; then
    n=$("$QPDF" --json "$TMP/flat.pdf" 2>/dev/null | grep -c '/Widget' || true)
    [ "$n" = "0" ] || fail "flatten left $n widget(s) in the output"
fi

# Flattening a file with no annotations still succeeds.
expect_ok "$PDFUTIL" flatten -o "$TMP/flat2.pdf" "$FIX/text.pdf"

# Overwrite policy.
expect_fail "$PDFUTIL" flatten -o "$TMP/flat.pdf" "$FIX/form-filled.pdf"
expect_ok   "$PDFUTIL" flatten -o "$TMP/flat.pdf" --force "$FIX/form-filled.pdf"

expect_ok "$PDFUTIL" flatten --help
