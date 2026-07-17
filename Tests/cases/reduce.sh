# reduce verb - recompress/downsample images (redraw path).

GRAY="/System/Library/Filters/Gray Tone.qfilter"

# Reducing an image-heavy PDF shrinks it and preserves the page count.
expect_ok "$PDFUTIL" reduce -o "$TMP/reduced.pdf" "$FIX/image.pdf"
insize=$(wc -c < "$FIX/image.pdf")
outsize=$(wc -c < "$TMP/reduced.pdf")
[ "$outsize" -lt "$insize" ] || fail "reduce did not shrink image.pdf ($insize -> $outsize)"
expect_grep "pages: 2" "$PDFUTIL" info "$TMP/reduced.pdf"

# A text/vector PDF still round-trips through the redraw with its text intact.
expect_ok "$PDFUTIL" reduce -o "$TMP/reduced-text.pdf" "$FIX/text.pdf"
expect_grep "PAGE-3-MARKER" "$PDFUTIL" text "$TMP/reduced-text.pdf"

# Metadata survives the redraw (the engine copies the Info attributes across).
cp "$FIX/image.pdf" "$TMP/titled.pdf"
expect_ok "$PDFUTIL" metadata --set title=ReduceMeta "$TMP/titled.pdf"
expect_ok "$PDFUTIL" reduce -o "$TMP/titled-r.pdf" "$TMP/titled.pdf"
expect_grep "title: ReduceMeta" "$PDFUTIL" metadata "$TMP/titled-r.pdf"

# --gray runs when the system filter is present (size may grow on some inputs).
if [ -f "$GRAY" ]; then
    expect_ok "$PDFUTIL" reduce --gray -o "$TMP/gray.pdf" "$FIX/image.pdf"
fi

# --filter is mutually exclusive with -q/-r/-m/--gray.
expect_code 1 "$PDFUTIL" reduce --filter "$GRAY" -q 50 -o "$TMP/x.pdf" "$FIX/image.pdf"

# Overwrite policy.
expect_fail "$PDFUTIL" reduce -o "$TMP/reduced.pdf" "$FIX/image.pdf"
expect_ok   "$PDFUTIL" reduce -o "$TMP/reduced.pdf" --force "$FIX/image.pdf"

expect_ok "$PDFUTIL" reduce --help
