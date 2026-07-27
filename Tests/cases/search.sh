# search verb - match location, count, ranges, zero-match behavior.

# "needle" appears once, on page 3.
expect_grep "p3:" "$PDFUTIL" search "$FIX/text.pdf" needle
expect_grep "^1$" "$PDFUTIL" search --count "$FIX/text.pdf" needle

# Restricting to a non-matching page yields zero.
expect_grep "^0$" "$PDFUTIL" search --count -p 1 "$FIX/text.pdf" needle

# A common marker word matches on every page.
expect_grep "^5$" "$PDFUTIL" search --count "$FIX/text.pdf" MARKER

# Zero matches: no stdout, exit 0.
out=$("$PDFUTIL" search "$FIX/text.pdf" zzznotpresent 2>/dev/null) || true
if [ -n "$out" ]; then fail "search with no matches produced output: $out"; fi
expect_ok "$PDFUTIL" search "$FIX/text.pdf" zzznotpresent

# JSON is valid.
"$PDFUTIL" search --json "$FIX/text.pdf" needle | python3 -m json.tool >/dev/null 2>&1 \
    || fail "search --json is not valid JSON"

# --count and --json are two output formats, not a format plus a modifier. The
# dispatch tested countOnly first, so --count silently won and the requested
# JSON never appeared.
expect_code 1 "$PDFUTIL" search --count --json "$FIX/text.pdf" needle
expect_ok "$PDFUTIL" search --count "$FIX/text.pdf" needle
expect_ok "$PDFUTIL" search --json "$FIX/text.pdf" needle

# --context only sizes the snippet, which --count does not print: 0, 20 and 99
# all produced the same total.
expect_code 1 "$PDFUTIL" search --count --context 0 "$FIX/text.pdf" needle
expect_ok "$PDFUTIL" search --context 40 "$FIX/text.pdf" needle
expect_ok "$PDFUTIL" search --json --context 40 "$FIX/text.pdf" needle

expect_ok "$PDFUTIL" search --help
