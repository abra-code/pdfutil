# frompages verb - images and PDFs into one PDF; rasterized product has no text.

# Render a page to PNG at 72 dpi (so pixels == points), then rebuild a PDF from
# it: the single page's media box should be 612x792.
expect_ok "$PDFUTIL" render -p 1 --dpi 72 -o "$TMP/p1.png" --force "$FIX/text.pdf"
expect_ok "$PDFUTIL" frompages -o "$TMP/fromimg.pdf" --force "$TMP/p1.png"
"$PDFUTIL" info --json "$TMP/fromimg.pdf" \
    | python3 -c 'import sys,json; p=json.load(sys.stdin)["pages"][0]["mediaBox"]; assert p["width"]==612 and p["height"]==792, p' \
    || fail "frompages image page is not 612x792"

# The rasterized product has no text layer (text verb exits 2).
expect_code 2 "$PDFUTIL" text "$TMP/fromimg.pdf"

# Mixed image + PDF: 1 image page + 5 PDF pages = 6 pages.
expect_ok "$PDFUTIL" frompages -o "$TMP/mixed.pdf" --force "$TMP/p1.png" "$FIX/text.pdf"
expect_grep "pages: 6" "$PDFUTIL" info "$TMP/mixed.pdf"

# The PDF-input pages retain their text (redraw re-records content).
expect_grep "PAGE-3-MARKER" "$PDFUTIL" text "$TMP/mixed.pdf"

# --dpi overrides the image DPI: at 144 dpi a 612px image becomes a 306 pt page.
expect_ok "$PDFUTIL" frompages --dpi 144 -o "$TMP/half.pdf" --force "$TMP/p1.png"
"$PDFUTIL" info --json "$TMP/half.pdf" \
    | python3 -c 'import sys,json; p=json.load(sys.stdin)["pages"][0]["mediaBox"]; assert p["width"]==306 and p["height"]==396, p' \
    || fail "frompages --dpi override did not resize the page"

# Missing -o and no inputs are usage errors; a non-finite --dpi is rejected.
expect_code 1 "$PDFUTIL" frompages "$TMP/p1.png"
expect_code 1 "$PDFUTIL" frompages -o "$TMP/x.pdf"
expect_code 1 "$PDFUTIL" frompages --dpi inf -o "$TMP/x.pdf" "$TMP/p1.png"

expect_ok "$PDFUTIL" frompages --help
