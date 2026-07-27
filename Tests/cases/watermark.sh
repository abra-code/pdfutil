# watermark verb - burn-in (text/image) and structure-preserving annotation mode.

# Burn-in text mark: page count is unchanged, the text layer survives the redraw,
# and the marked page still renders.
expect_ok "$PDFUTIL" watermark --text DRAFT -o "$TMP/wm.pdf" "$FIX/text.pdf"
expect_grep "pages: 5" "$PDFUTIL" info "$TMP/wm.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text "$TMP/wm.pdf"
expect_ok "$PDFUTIL" render -p 1 --dpi 40 -o "$TMP/wm.png" "$TMP/wm.pdf"

# Burn-in image mark (a rendered page reused as a logo).
expect_ok "$PDFUTIL" render -p 1 --dpi 30 -o "$TMP/logo.png" "$FIX/image.pdf"
expect_ok "$PDFUTIL" watermark --image "$TMP/logo.png" --opacity 40 -o "$TMP/wmimg.pdf" "$FIX/text.pdf"
expect_grep "pages: 5" "$PDFUTIL" info "$TMP/wmimg.pdf"

# --under and a corner position are accepted.
expect_ok "$PDFUTIL" watermark --text SAMPLE --under --position top-left -o "$TMP/wmu.pdf" "$FIX/text.pdf"

# Annotation mode is structure-preserving: the outline survives and a freeText
# annotation is added (burn-in leaves 0 annotations; annotation mode leaves 1).
expect_ok "$PDFUTIL" watermark --text CONFIDENTIAL --annotation -o "$TMP/anno.pdf" "$FIX/outline.pdf"
expect_grep "Chapter 1" "$PDFUTIL" outline "$TMP/anno.pdf"
expect_grep '"annotations" : 1' "$PDFUTIL" info --json "$TMP/anno.pdf"

# -p marks a subset; the whole document is still emitted (5 pages).
expect_ok "$PDFUTIL" watermark --text MARK -p 2 -o "$TMP/wmp.pdf" "$FIX/text.pdf"
expect_grep "pages: 5" "$PDFUTIL" info "$TMP/wmp.pdf"

# Argument errors.
expect_code 1 "$PDFUTIL" watermark -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" watermark --text A --image "$TMP/logo.png" -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" watermark --image "$TMP/logo.png" --annotation -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" watermark --text A --opacity 150 -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" watermark --text A --position middle -o "$TMP/x.pdf" "$FIX/text.pdf"

# Overwrite policy.
expect_fail "$PDFUTIL" watermark --text DRAFT -o "$TMP/wm.pdf" "$FIX/text.pdf"
expect_ok   "$PDFUTIL" watermark --text DRAFT -o "$TMP/wm.pdf" --force "$FIX/text.pdf"

# watermarkAnnotation reads text/position/opacity/point-size and nothing else,
# so --rotate-mark and --under were accepted and dropped: an
# `--annotation --under` run produced byte-identical output to one without it.
expect_code 1 "$PDFUTIL" watermark --text A --annotation --under -o "$TMP/x.pdf" --force "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" watermark --text A --annotation --rotate-mark 30 -o "$TMP/x.pdf" --force "$FIX/text.pdf"
# Both remain valid on the burn-in path, and --annotation alone still works.
expect_ok "$PDFUTIL" watermark --text A --under --rotate-mark 30 -o "$TMP/x.pdf" --force "$FIX/text.pdf"
expect_ok "$PDFUTIL" watermark --text A --annotation -o "$TMP/x.pdf" --force "$FIX/text.pdf"

# drawImageMark scales the image to the page and never reads pointSize, so an
# image mark took --point-size and dropped it (5 and 500 gave identical output).
python3 -c "import base64,sys;open(sys.argv[1],'wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))" "$TMP/wmark.png"
expect_code 1 "$PDFUTIL" watermark --image "$TMP/wmark.png" --point-size 24 -o "$TMP/x.pdf" --force "$FIX/text.pdf"
# It still applies to both text paths, and an image mark still works without it.
expect_ok "$PDFUTIL" watermark --text A --point-size 24 -o "$TMP/x.pdf" --force "$FIX/text.pdf"
expect_ok "$PDFUTIL" watermark --text A --annotation --point-size 24 -o "$TMP/x.pdf" --force "$FIX/text.pdf"
expect_ok "$PDFUTIL" watermark --image "$TMP/wmark.png" -o "$TMP/x.pdf" --force "$FIX/text.pdf"

expect_ok "$PDFUTIL" watermark --help
