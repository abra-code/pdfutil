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

# --filter is mutually exclusive with -q/-r/-m/--gray. The --gray leg matters
# most: it is the one whose representation changed when sawImageFlag became a
# separate recompressFlags list plus an options.gray term, so it is the only
# place this exclusion could have silently regressed.
expect_code 1 "$PDFUTIL" reduce --filter "$GRAY" -q 50 -o "$TMP/x.pdf" "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" reduce --filter "$GRAY" -r 72 -o "$TMP/x.pdf" "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" reduce --filter "$GRAY" -m 500 -o "$TMP/x.pdf" "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" reduce --filter "$GRAY" --gray -o "$TMP/x.pdf" "$FIX/image.pdf"

# Overwrite policy.
expect_fail "$PDFUTIL" reduce -o "$TMP/reduced.pdf" "$FIX/image.pdf"
expect_ok   "$PDFUTIL" reduce -o "$TMP/reduced.pdf" --force "$FIX/image.pdf"

# --gray replaces recompression rather than tuning it: buildReduceFilter returns
# the Gray Tone filter before it reads quality/dpi/maxEdge, so these three were
# accepted and dropped (-q 1 and -q 100 gave byte-identical output). The MCP
# twin pdf_reduce has always refused this; the CLI verb now matches it.
expect_code 1 "$PDFUTIL" reduce --gray -q 50 -o "$TMP/x.pdf" --force "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" reduce --gray -r 72 -o "$TMP/x.pdf" --force "$FIX/image.pdf"
expect_code 1 "$PDFUTIL" reduce --gray -m 500 -o "$TMP/x.pdf" --force "$FIX/image.pdf"
# Each half stays valid on its own.
expect_ok "$PDFUTIL" reduce --gray -o "$TMP/x.pdf" --force "$FIX/image.pdf"
expect_ok "$PDFUTIL" reduce -q 50 -r 72 -m 500 -o "$TMP/x.pdf" --force "$FIX/image.pdf"

expect_ok "$PDFUTIL" reduce --help

# --- the recompression-grew-the-file guard -------------------------------
#
# Quartz applies the JPEG setting only to images it RESCALES. Handed scale
# settings that match nothing it decodes each image and re-encodes it LOSSLESSLY
# as Flate, so a document of JPEG photos grows several-fold. Measured in the
# wild: a 7.4 MB two-photo PDF became 54.4 MB.
#
# Build that shape from the fixtures: render a page to JPEG, force its recorded
# DPI to 72, and assemble it. The page is then as many points as the image has
# pixels, so every image sits at exactly 72 DPI and -r can never fire on it.
expect_ok "$PDFUTIL" render -p 1 --dpi 200 --force -o "$TMP/red-src.jpg" "$FIX/image.pdf"
/usr/bin/sips -s dpiWidth 72 -s dpiHeight 72 "$TMP/red-src.jpg" --out "$TMP/red-src72.jpg" >/dev/null 2>&1
expect_ok "$PDFUTIL" frompages --force -o "$TMP/grow.pdf" "$TMP/red-src72.jpg"

# A reduce that could only make the file bigger keeps the original instead, and
# still exits 0 - nothing failed, there was simply nothing to gain.
growin=$(wc -c < "$TMP/grow.pdf")
expect_code 0 "$PDFUTIL" reduce -m 0 --force -o "$TMP/grown.pdf" "$TMP/grow.pdf"
growout=$(wc -c < "$TMP/grown.pdf")
[ "$growout" -le "$growin" ] || fail "reduce kept a larger result ($growin -> $growout)"
cmp -s "$TMP/grow.pdf" "$TMP/grown.pdf" || fail "reduce did not copy the original to -o when it declined its result"
"$PDFUTIL" reduce -m 0 --force -o "$TMP/grown.pdf" "$TMP/grow.pdf" 2>&1 \
    | grep -q "kept the original" \
    || fail "reduce did not report that it kept the original"

# In place, the input is not touched at all.
cp "$TMP/grow.pdf" "$TMP/growip.pdf"
before=$(shasum < "$TMP/growip.pdf")
expect_code 0 "$PDFUTIL" reduce -m 0 "$TMP/growip.pdf"
[ "$before" = "$(shasum < "$TMP/growip.pdf")" ] || fail "in-place reduce modified a file it declined to shrink"

# -o naming the input must not destroy it (the copy-onto-itself trap).
cp "$TMP/grow.pdf" "$TMP/self.pdf"
expect_code 0 "$PDFUTIL" reduce -m 0 --force -o "$TMP/self.pdf" "$TMP/self.pdf"
cmp -s "$TMP/grow.pdf" "$TMP/self.pdf" || fail "reduce -o naming the input corrupted it"

# --gray is EXEMPT: the transformation is what was asked for, so its output is
# kept whatever it weighs. Without the exemption a grayscale run that grew would
# silently return a color document.
if [ -f "$GRAY" ]; then
    expect_ok "$PDFUTIL" reduce --gray --force -o "$TMP/graygrow.pdf" "$TMP/grow.pdf"
    if "$PDFUTIL" reduce --gray --force -o "$TMP/graygrow.pdf" "$TMP/grow.pdf" 2>&1 \
         | grep -q "kept the original"; then
        fail "--gray output was discarded for growing; the transformation is the point"
    fi
fi

# The default cap is 2400, not off: it is what makes the JPEG setting take
# effect at all.
#
# -r 0 here is what makes the assertion mean anything. With resolution
# downsampling left on, an image recorded at 400 DPI is already above the 150
# DPI threshold, so -r shrinks it and the result lands under 2400 whether or not
# the cap exists - the test would still pass with --max-edge defaulted back to
# off. Forcing the image to 72 DPI and disabling -r leaves the cap as the only
# mechanism that can act.
expect_ok "$PDFUTIL" render -p 1 --dpi 400 --force -o "$TMP/red-wide.png" "$FIX/image.pdf"
/usr/bin/sips -s dpiWidth 72 -s dpiHeight 72 "$TMP/red-wide.png" --out "$TMP/red-wide72.png" >/dev/null 2>&1
expect_ok "$PDFUTIL" frompages --force -o "$TMP/red-wide.pdf" "$TMP/red-wide72.png"
expect_ok "$PDFUTIL" reduce -r 0 --force -o "$TMP/red-widered.pdf" "$TMP/red-wide.pdf"
python3 - "$TMP/red-wide.pdf" "$TMP/red-widered.pdf" <<'EDGES' || fail "default --max-edge did not cap the longest image edge at 2400 px"
import re, sys


def edges(path):
    d = open(path, 'rb').read()
    w = [int(m.group(1)) for m in re.finditer(rb'/Subtype\s*/Image.{0,400}?/Width\s+(\d+)', d, re.S)]
    h = [int(m.group(1)) for m in re.finditer(rb'/Subtype\s*/Image.{0,400}?/Height\s+(\d+)', d, re.S)]
    return w + h


before, after = edges(sys.argv[1]), edges(sys.argv[2])
# The source really is over the cap, or the assertion below proves nothing.
assert before and max(before) > 2400, before
assert after and max(after) <= 2400, after
EDGES

# --- symlinked inputs ------------------------------------------------------
#
# attributesOfItem is lstat-like, so a symlink reports the length of its target
# STRING. That was cosmetic while the size only fed the printed report; the
# growth guard turned it into a decision, and an 8-byte "input size" made every
# real result look like a catastrophic expansion. reduce then declined on every
# symlinked input and shipped a copy of the LINK - FileManager.copyItem copies a
# symlink as a symlink - so -o produced an 8-byte file where a PDF was promised.
ln -sf "red-src72.jpg" "$TMP/red-link.jpg" 2>/dev/null
cp "$FIX/image.pdf" "$TMP/sym-real.pdf"
ln -sf "sym-real.pdf" "$TMP/sym-link.pdf"
expect_ok "$PDFUTIL" reduce --force -o "$TMP/sym-out.pdf" "$TMP/sym-link.pdf"
symsize=$(wc -c < "$TMP/sym-out.pdf")
realsize=$(wc -c < "$TMP/sym-real.pdf")
[ "$symsize" -gt 1000 ] || fail "reduce through a symlink produced a $symsize-byte file (copied the link, not the document)"
[ "$symsize" -lt "$realsize" ] || fail "reduce through a symlink did not shrink ($realsize -> $symsize)"
expect_grep "%PDF-" /usr/bin/head -c 5 "$TMP/sym-out.pdf"

# The destructive shape: the input is a symlink and -o names the file it points
# at. Those are the same document, so there is nothing to copy - and the earlier
# remove-then-copy turned it into a symlink pointing at itself, destroying the
# only copy of the data.
cp "$TMP/grow.pdf" "$TMP/sym-target.pdf"
ln -sf "sym-target.pdf" "$TMP/sym-in.pdf"
targetsize=$(wc -c < "$TMP/sym-target.pdf")
expect_code 0 "$PDFUTIL" reduce -m 0 --force -o "$TMP/sym-target.pdf" "$TMP/sym-in.pdf"
[ -f "$TMP/sym-target.pdf" ] || fail "reduce destroyed the file its symlinked input pointed at"
[ "$(wc -c < "$TMP/sym-target.pdf")" -eq "$targetsize" ] || fail "reduce altered the target of a symlinked input it declined to shrink"
expect_grep "%PDF-" /usr/bin/head -c 5 "$TMP/sym-target.pdf"

# The declined path must still honor the create-only policy: an output that
# exists without --force is refused rather than removed and replaced.
printf 'not a pdf' > "$TMP/sym-taken.pdf"
expect_fail "$PDFUTIL" reduce -m 0 -o "$TMP/sym-taken.pdf" "$TMP/grow.pdf"
expect_grep "not a pdf" /bin/cat "$TMP/sym-taken.pdf"
