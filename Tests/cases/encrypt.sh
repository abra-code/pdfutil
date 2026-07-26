# encrypt / decrypt verbs - password round-trip and permission flags.

# Encrypt with a user password; the output cannot be read without it.
expect_ok "$PDFUTIL" encrypt --user-password secret -o "$TMP/enc.pdf" "$FIX/text.pdf"
expect_code 2 "$PDFUTIL" text "$TMP/enc.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text --password secret "$TMP/enc.pdf"

# Decrypt restores an openable file.
expect_ok "$PDFUTIL" decrypt --password secret -o "$TMP/dec.pdf" "$TMP/enc.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text "$TMP/dec.pdf"

# Structural check on the raw bytes: the encryption dictionary is required to be
# unencrypted and outside any object stream, so a byte grep sees it without
# needing any crypto support. This is the primary assertion - it always runs.
assert_encrypted() {
    if ! LC_ALL=C grep -aqE '/Encrypt[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+R' "$1"; then
        fail "$1: trailer carries no /Encrypt reference"
    fi
    if ! LC_ALL=C grep -aqE '/Filter[[:space:]]*/Standard' "$1"; then
        fail "$1: no standard security handler dictionary"
    fi
    if ! LC_ALL=C grep -aqE '/(AESV2|AESV3|V2)' "$1"; then
        fail "$1: encryption dictionary names no scheme"
    fi
}
assert_not_encrypted() {
    if LC_ALL=C grep -aqE '/Encrypt[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+R' "$1"; then
        fail "$1: still carries an /Encrypt reference"
    fi
}
assert_encrypted "$TMP/enc.pdf"
assert_not_encrypted "$TMP/dec.pdf"

# qpdf cross-checks the same two files (guarded on qpdf's presence). Reporting a
# file as unencrypted needs no crypto, but opening one does: PDFKit writes V4/R4
# (AES-128), whose key derivation runs RC4, which lives in OpenSSL's legacy
# provider. qpdf builds that cannot load that provider refuse R<=4 files
# outright, so treat that as a skip rather than a failure.
if [ -x "$QPDF" ]; then
    "$QPDF" --show-encryption "$TMP/dec.pdf" 2>/dev/null | grep -qi "not encrypted" \
        || fail "decrypt output is still encrypted"
    qenc=$("$QPDF" --show-encryption --password=secret "$TMP/enc.pdf" 2>&1 || true)
    case "$qenc" in
        *"legacy provider"*)
            echo "  (skipping qpdf encryption check: no openssl legacy provider)" ;;
        *)
            printf '%s\n' "$qenc" | grep -qiE "R = |bits" \
                || fail "encrypt output does not report an encryption scheme" ;;
    esac
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
