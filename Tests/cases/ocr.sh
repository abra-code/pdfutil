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

expect_ok "$PDFUTIL" ocr --help
