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

# --- --page-size: scale each image to fit a fixed page --------------------
#
# Without it a page is as large as its image claims to be, and cameras record
# 72 DPI, so a 4284 px photo becomes a 59-inch page. Faithful, rarely wanted,
# and it defeats `reduce -r`, which measures resolution against the page.

# A portrait image on letter gives a portrait letter page.
expect_ok "$PDFUTIL" frompages --page-size letter -o "$TMP/ps.pdf" --force "$TMP/p1.png"
"$PDFUTIL" info --json "$TMP/ps.pdf" \
    | python3 -c 'import sys,json; p=json.load(sys.stdin)["pages"][0]["mediaBox"]; assert p["width"]==612 and p["height"]==792, p' \
    || fail "--page-size letter did not produce a 612x792 page"

# The page is ORIENTED to the image: a landscape source gets a landscape page
# rather than a portrait one with deep white bands top and bottom.
expect_ok "$PDFUTIL" render -p 1 --dpi 72 -o "$TMP/land.png" --force "$FIX/rotated.pdf"
expect_ok "$PDFUTIL" frompages --page-size letter -o "$TMP/psland.pdf" --force "$TMP/land.png"
"$PDFUTIL" info --json "$TMP/psland.pdf" \
    | python3 -c '
import sys, json
box = json.load(sys.stdin)["pages"][0]["mediaBox"]
w, h = box["width"], box["height"]
assert {round(w), round(h)} == {612, 792}, box
assert w > h, ("landscape image did not get a landscape page", box)
' || fail "--page-size did not orient the page to a landscape image"

# Named sizes and explicit WxH both parse; a4 is 595x842.
expect_ok "$PDFUTIL" frompages --page-size a4 -o "$TMP/psa4.pdf" --force "$TMP/p1.png"
"$PDFUTIL" info --json "$TMP/psa4.pdf" \
    | python3 -c 'import sys,json; p=json.load(sys.stdin)["pages"][0]["mediaBox"]; assert p["width"]==595 and p["height"]==842, p' \
    || fail "--page-size a4 did not produce a 595x842 page"
expect_ok "$PDFUTIL" frompages --page-size 300x400 -o "$TMP/psxy.pdf" --force "$TMP/p1.png"
"$PDFUTIL" info --json "$TMP/psxy.pdf" \
    | python3 -c 'import sys,json; p=json.load(sys.stdin)["pages"][0]["mediaBox"]; assert p["width"]==300 and p["height"]==400, p' \
    || fail "--page-size WxH did not produce a 300x400 page"

# Case is not significant, and a garbage value is refused rather than defaulted.
expect_ok   "$PDFUTIL" frompages --page-size LETTER -o "$TMP/psup.pdf" --force "$TMP/p1.png"
expect_code 1 "$PDFUTIL" frompages --page-size huge -o "$TMP/x.pdf" --force "$TMP/p1.png"
expect_code 1 "$PDFUTIL" frompages --page-size 0x400 -o "$TMP/x.pdf" --force "$TMP/p1.png"
expect_code 1 "$PDFUTIL" frompages --page-size 612x -o "$TMP/x.pdf" --force "$TMP/p1.png"

# --page-size and --dpi both decide how big a page is, so the pair is refused
# rather than one of them silently winning.
expect_code 1 "$PDFUTIL" frompages --page-size letter --dpi 144 -o "$TMP/x.pdf" --force "$TMP/p1.png"

# The point of the option: a fitted document is one `reduce` can actually shrink,
# because its images now sit at a real resolution relative to the page.
#
# The source has to be genuinely bigger than reduce's 2400 px cap or this proves
# nothing. p1.png is a 612 px render, so on a letter page nothing can fire and
# reduce declines - and because a declined reduce copies the original, "output
# is not larger than input" would then hold no matter what the option did. It
# has to be a STRICT shrink, and the bytes have to actually differ.
expect_ok "$PDFUTIL" render -p 1 --dpi 320 -o "$TMP/psbig.png" --force "$FIX/image.pdf"
expect_ok "$PDFUTIL" frompages --page-size letter -o "$TMP/psbig.pdf" --force "$TMP/psbig.png"
expect_ok "$PDFUTIL" reduce --force -o "$TMP/psred.pdf" "$TMP/psbig.pdf"
psin=$(wc -c < "$TMP/psbig.pdf")
psout=$(wc -c < "$TMP/psred.pdf")
[ "$psout" -lt "$psin" ] || fail "reduce did not shrink a fit-to-page document ($psin -> $psout)"
if cmp -s "$TMP/psbig.pdf" "$TMP/psred.pdf"; then
    fail "reduce returned the original for a fit-to-page document instead of recompressing it"
fi
