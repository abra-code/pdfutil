# forms verb - list, fill, and flatten AcroForm fields.

# --list --json reports both fixture fields.
expect_grep '"name" : "name"' "$PDFUTIL" forms --list --json "$FIX/form.pdf"
expect_grep '"name" : "agree"' "$PDFUTIL" forms --list --json "$FIX/form.pdf"

# Fill the fields, then a plain list shows the new values.
printf '{"name":"Bob","agree":true}' > "$TMP/fill.json"
expect_ok "$PDFUTIL" forms --fill "$TMP/fill.json" -o "$TMP/filled.pdf" "$FIX/form.pdf"
expect_grep "name (text) = Bob" "$PDFUTIL" forms "$TMP/filled.pdf"
expect_grep "agree (button) = on" "$PDFUTIL" forms "$TMP/filled.pdf"

# Fill and flatten: the value burns into the page text and the widgets are gone.
expect_ok "$PDFUTIL" forms --fill "$TMP/fill.json" --flatten -o "$TMP/flatf.pdf" "$FIX/form.pdf"
expect_grep "Bob" "$PDFUTIL" text "$TMP/flatf.pdf"
expect_grep "no form fields" "$PDFUTIL" forms "$TMP/flatf.pdf"

# An unknown field name is a processing error (exit 2) listing the real names.
printf '{"nope":"x"}' > "$TMP/bad.json"
expect_code 2 "$PDFUTIL" forms --fill "$TMP/bad.json" -o "$TMP/x.pdf" "$FIX/form.pdf"

# A wrong value type is a usage error (exit 1).
printf '{"agree":"yes"}' > "$TMP/badtype.json"
expect_code 1 "$PDFUTIL" forms --fill "$TMP/badtype.json" -o "$TMP/x.pdf" "$FIX/form.pdf"

# --list and the mutation flags are mutually exclusive.
expect_code 1 "$PDFUTIL" forms --list --fill "$TMP/fill.json" -o "$TMP/x.pdf" "$FIX/form.pdf"

# A file with no form fields lists cleanly.
expect_grep "no form fields" "$PDFUTIL" forms "$FIX/text.pdf"

expect_ok "$PDFUTIL" forms --help
