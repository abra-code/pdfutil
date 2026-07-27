# render verb - pixel dimensions, rotation, formats, multi-page naming.

pxwh() { sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}'; }

# A US Letter page at 72 dpi is exactly 612x792 pixels.
expect_ok "$PDFUTIL" render -p 1 --dpi 72 -o "$TMP/r.png" "$FIX/text.pdf"
[ "$(pxwh "$TMP/r.png")" = "612x792" ] || fail "render 72dpi is not 612x792 (got $(pxwh "$TMP/r.png"))"

# A rotated page renders landscape (rotation is applied).
expect_ok "$PDFUTIL" render -p 1 --dpi 72 -o "$TMP/rr.png" "$FIX/rotated.pdf"
[ "$(pxwh "$TMP/rr.png")" = "792x612" ] || fail "rotated render is not 792x612 (got $(pxwh "$TMP/rr.png"))"

# --scale 1 equals 72 dpi.
expect_ok "$PDFUTIL" render -p 1 --scale 1 -o "$TMP/rs.png" --force "$FIX/text.pdf"
[ "$(pxwh "$TMP/rs.png")" = "612x792" ] || fail "render --scale 1 is not 612x792"

# JPEG with a quality flag is accepted.
expect_ok "$PDFUTIL" render -p 1 --dpi 72 --format jpeg --quality 60 -o "$TMP/r.jpg" "$FIX/text.pdf"

# Multi-page produces zero-padded NNN files with a prefix.
expect_ok "$PDFUTIL" render -p 1-3 --dpi 36 -o "$TMP/multi" "$FIX/text.pdf"
[ -f "$TMP/multi-001.png" ] && [ -f "$TMP/multi-003.png" ] || fail "render multi-page naming failed"

# Overwrite policy and mutually-exclusive / invalid options.
expect_fail  "$PDFUTIL" render -p 1 --dpi 72 -o "$TMP/r.png" "$FIX/text.pdf"
expect_ok    "$PDFUTIL" render -p 1 --dpi 72 -o "$TMP/r.png" --force "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" render --dpi 72 --scale 2 -o "$TMP/x.png" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" render --format jpeg --transparent -o "$TMP/x.jpg" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" render --format bogus -o "$TMP/x.png" "$FIX/text.pdf"

# Extreme/degenerate DPI values must fail cleanly (exit 1/2), never crash.
expect_code 1 "$PDFUTIL" render --dpi inf -o "$TMP/x.png" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" render --scale inf -o "$TMP/x.png" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" render --dpi 0 -o "$TMP/x.png" "$FIX/text.pdf"
expect_code 2 "$PDFUTIL" render --dpi 500000 -o "$TMP/x.png" "$FIX/text.pdf"
expect_code 2 "$PDFUTIL" render --dpi 1e19 -o "$TMP/x.png" "$FIX/text.pdf"

# -o reused as a multi-page prefix drops a trailing image extension.
expect_ok "$PDFUTIL" render -p 1-2 --dpi 36 -o "$TMP/pref.png" --force "$FIX/text.pdf"
[ -f "$TMP/pref-001.png" ] || fail "render prefix did not strip the .png extension"

# writeCGImage applies quality only when the format is lossy, so png/tiff took
# --quality and threw it away (1 and 100 gave byte-identical files). This is the
# same rule --transparent already enforced for its own unsupported formats.
expect_code 1 "$PDFUTIL" render -p 1 --format png --quality 50 -o "$TMP/x.png" --force "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" render -p 1 --format tiff --quality 50 -o "$TMP/x.tiff" --force "$FIX/text.pdf"
# Lossy formats still take it; the non-lossy formats still work without it.
expect_ok "$PDFUTIL" render -p 1 --format jpeg --quality 50 -o "$TMP/x.jpg" --force "$FIX/text.pdf"
expect_ok "$PDFUTIL" render -p 1 --format heic --quality 50 -o "$TMP/x.heic" --force "$FIX/text.pdf"
expect_ok "$PDFUTIL" render -p 1 --format png -o "$TMP/x.png" --force "$FIX/text.pdf"

expect_ok "$PDFUTIL" render --help
