# crop verb - margins inset, absolute rect, box selection, validation.

# --margins 36,36,36,36 shrinks the crop box by 72 in each dimension: 540x720.
expect_ok "$PDFUTIL" crop --margins 36,36,36,36 -o "$TMP/cropm.pdf" "$FIX/text.pdf"
"$PDFUTIL" info --json "$TMP/cropm.pdf" \
    | python3 -c 'import sys,json; p=json.load(sys.stdin)["pages"][0]["cropBox"]; assert p["width"]==540 and p["height"]==720, p' \
    || fail "crop --margins did not produce a 540x720 crop box"

# --rect sets an absolute box.
expect_ok "$PDFUTIL" crop --rect 0,0,300,400 -o "$TMP/cropr.pdf" "$FIX/text.pdf"
"$PDFUTIL" info --json "$TMP/cropr.pdf" \
    | python3 -c 'import sys,json; p=json.load(sys.stdin)["pages"][0]["cropBox"]; assert p["width"]==300 and p["height"]==400, p' \
    || fail "crop --rect did not produce a 300x400 crop box"

# Requiring exactly one of --rect/--margins, and rejecting an empty result.
expect_code 1 "$PDFUTIL" crop -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" crop --rect 0,0,300,400 --margins 1,1,1,1 "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" crop --margins 400,400,400,400 -o "$TMP/x.pdf" "$FIX/text.pdf"

expect_ok "$PDFUTIL" crop --help
