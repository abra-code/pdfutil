# encrypt / decrypt verbs - password round-trip and permission flags.

QPDF="/Users/tkukielk/Development/QuickPDFApp/QuickPDF.app/Contents/Helpers/qpdf"

# Encrypt with a user password; the output cannot be read without it.
expect_ok "$PDFUTIL" encrypt --user-password secret -o "$TMP/enc.pdf" "$FIX/text.pdf"
expect_code 2 "$PDFUTIL" text "$TMP/enc.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text --password secret "$TMP/enc.pdf"

# Decrypt restores an openable file.
expect_ok "$PDFUTIL" decrypt --password secret -o "$TMP/dec.pdf" "$TMP/enc.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text "$TMP/dec.pdf"

# qpdf confirms the output is unencrypted (guarded on qpdf's presence).
if [ -x "$QPDF" ]; then
    "$QPDF" --show-encryption "$TMP/dec.pdf" 2>/dev/null | grep -qi "not encrypted" \
        || fail "decrypt output is still encrypted"
    "$QPDF" --show-encryption --password=secret "$TMP/enc.pdf" 2>/dev/null | grep -qiE "R = |bits" \
        || fail "encrypt output does not report an encryption scheme"
fi

# Permissions: a user-password reader is limited to --allow; the owner is not.
expect_ok "$PDFUTIL" encrypt --user-password u --owner-password o --allow printing \
    -o "$TMP/encp.pdf" "$FIX/text.pdf"
expect_grep "permissions: printing" "$PDFUTIL" info --password u "$TMP/encp.pdf"
expect_nogrep "copying" "$PDFUTIL" info --password u "$TMP/encp.pdf"

# Passwords may be read from stdin instead of argv (the -stdin family).
printf 'pipepw' | expect_ok "$PDFUTIL" encrypt --user-password-stdin -o "$TMP/encs.pdf" "$FIX/text.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text --password pipepw "$TMP/encs.pdf"
printf 'pipepw' | expect_ok "$PDFUTIL" decrypt --password-stdin -o "$TMP/decs.pdf" "$TMP/encs.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text "$TMP/decs.pdf"

# A flag and its -stdin form are mutually exclusive; only one stdin password.
printf 'x' | expect_code 1 "$PDFUTIL" encrypt --user-password u --user-password-stdin -o "$TMP/x.pdf" "$FIX/text.pdf"
printf 'x' | expect_code 1 "$PDFUTIL" encrypt --user-password-stdin --owner-password-stdin -o "$TMP/x.pdf" "$FIX/text.pdf"
printf 'x' | expect_code 1 "$PDFUTIL" decrypt --password p --password-stdin "$TMP/encs.pdf"
# An empty stdin password is a usage error, not a silent empty password.
printf '' | expect_code 1 "$PDFUTIL" decrypt --password-stdin "$TMP/encs.pdf"

# Argument errors.
expect_code 1 "$PDFUTIL" encrypt -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" encrypt --user-password p --allow bogus -o "$TMP/x.pdf" "$FIX/text.pdf"
expect_code 1 "$PDFUTIL" decrypt -o "$TMP/x.pdf" "$TMP/enc.pdf"

expect_ok "$PDFUTIL" encrypt --help
expect_ok "$PDFUTIL" decrypt --help
