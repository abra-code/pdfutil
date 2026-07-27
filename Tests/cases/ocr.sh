# ocr verb - Vision recognition (print) and PDFKit searchable-layer embedding.

# (a) OCR of the image-only scan recovers its text.
expect_grep "OCRTEST" "$PDFUTIL" ocr -p 1 "$FIX/image.pdf"
expect_grep "12345"   "$PDFUTIL" ocr -p 1 "$FIX/image.pdf"

# (b) --searchable embeds a text layer that the text verb can then extract.
expect_ok "$PDFUTIL" ocr --searchable -o "$TMP/searchable.pdf" "$FIX/image.pdf"
expect_grep "OCRTEST" "$PDFUTIL" text "$TMP/searchable.pdf"
expect_grep "SECOND PAGE SCAN" "$PDFUTIL" text "$TMP/searchable.pdf"

# ocr always rasterizes, so it also recognizes a real-text page's rendering.
expect_grep "PAGE-3-MARKER" "$PDFUTIL" ocr -p 3 "$FIX/text.pdf"

# A recognition language is accepted.
expect_ok "$PDFUTIL" ocr -p 1 --lang en-US "$FIX/image.pdf"

# --searchable requires -o; overwrite policy applies to the output.
expect_code 1 "$PDFUTIL" ocr --searchable "$FIX/image.pdf"
expect_fail "$PDFUTIL" ocr --searchable -o "$TMP/searchable.pdf" "$FIX/image.pdf"
expect_ok   "$PDFUTIL" ocr --searchable -o "$TMP/searchable.pdf" --force "$FIX/image.pdf"

# --searchable is PDFKit's whole-document OCR-embed, which cannot honor the
# rasterize path's controls. These were once accepted and silently dropped:
# `ocr --searchable -p 1` OCR'd all three pages of a scan, and `-p 99` on a
# 3-page file exited 0 because the range validation lives on the other branch.
expect_code 1 "$PDFUTIL" ocr --searchable -p 1 -o "$TMP/x.pdf" --force "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" ocr --searchable -p 99 -o "$TMP/x.pdf" --force "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" ocr --searchable --lang en-US -o "$TMP/x.pdf" --force "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" ocr --searchable --fast -o "$TMP/x.pdf" --force "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" ocr --searchable --dpi 200 -o "$TMP/x.pdf" --force "$FIX/image.pdf"
# ...while each remains valid on the rasterize path, and --searchable alone still works.
expect_ok "$PDFUTIL" ocr -p 1 --lang en-US --fast --dpi 200 "$FIX/image.pdf"
expect_ok "$PDFUTIL" ocr --searchable -o "$TMP/x.pdf" --force "$FIX/image.pdf"
# The guard is validated from parsed state before the input is opened, so a bad
# command line is exit 1 (usage) whatever the file turns out to be - not exit 2
# for a missing or locked input that was never the user's actual mistake.
expect_code 1 "$PDFUTIL" ocr --searchable -p 1 -o "$TMP/x.pdf" --force "$TMP/no-such-file.pdf"
expect_code 1 "$PDFUTIL" ocr --searchable -p 1 -o "$TMP/x.pdf" --force "$FIX/locked.pdf"
expect_code 1 "$PDFUTIL" ocr --searchable "$TMP/no-such-file.pdf"

expect_ok "$PDFUTIL" ocr --help
