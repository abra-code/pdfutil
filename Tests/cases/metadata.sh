# metadata verb - read, set, strip.

# Reading metadata on a plain file works.
expect_ok "$PDFUTIL" metadata "$FIX/text.pdf"

# Set a title, then read it back (human and JSON).
cp "$FIX/text.pdf" "$TMP/meta.pdf"
expect_ok "$PDFUTIL" metadata --set title=Hello --set author=Alice "$TMP/meta.pdf"
expect_grep "title: Hello" "$PDFUTIL" metadata "$TMP/meta.pdf"
expect_grep '"title" : "Hello"' "$PDFUTIL" metadata --json "$TMP/meta.pdf"
expect_grep '"author" : "Alice"' "$PDFUTIL" metadata --json "$TMP/meta.pdf"

# Keywords are comma-split into an array.
expect_ok "$PDFUTIL" metadata --set keywords=one,two,three "$TMP/meta.pdf"
expect_grep "keywords: one, two, three" "$PDFUTIL" metadata "$TMP/meta.pdf"

# --strip removes all attributes, so the title is gone.
expect_ok "$PDFUTIL" metadata --strip "$TMP/meta.pdf"
expect_nogrep "title: Hello" "$PDFUTIL" metadata "$TMP/meta.pdf"

# An unknown key and a bad date are usage errors.
expect_code 1 "$PDFUTIL" metadata --set bogus=1 -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" metadata --set creation-date=notadate -o "$TMP/x.pdf" "$FIX/text.pdf"

expect_ok "$PDFUTIL" metadata --help
