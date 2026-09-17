# Protected PDFs that open without a password: permission restrictions, and a
# protection PDFKit cannot re-save. Every refusal must exit 2 and write nothing -
# before this, PDFKit skipped the refused edit, the unchanged copy was saved, and
# the run reported success.

# restricted.pdf allows printing and copying only. Each edit PDFKit would skip is
# refused up front and names the missing permission.
expect_code 2 "$PDFUTIL" pages --delete 1 -o "$TMP/r-del.pdf" "$FIX/restricted.pdf"
expect_grep "do not allow removing pages" sh -c '"$1" pages --delete 1 -o "$2" "$3" 2>&1' _ "$PDFUTIL" "$TMP/r-del.pdf" "$FIX/restricted.pdf"
expect_code 2 "$PDFUTIL" rotate 90 -o "$TMP/r-rot.pdf" "$FIX/restricted.pdf"
expect_code 2 "$PDFUTIL" metadata --set title=X -o "$TMP/r-meta.pdf" "$FIX/restricted.pdf"
expect_code 2 "$PDFUTIL" watermark --annotation --text DRAFT -o "$TMP/r-wm.pdf" "$FIX/restricted.pdf"
printf '{"name": "Bob"}' > "$TMP/r-fill.json"
expect_code 2 "$PDFUTIL" forms --fill "$TMP/r-fill.json" -o "$TMP/r-fill.pdf" "$FIX/restricted-form.pdf"
for refused in r-del r-rot r-meta r-wm r-fill; do
    if [ -e "$TMP/$refused.pdf" ]; then fail "$refused: a refused edit still wrote $TMP/$refused.pdf"; fi
done

# In place, a refusal leaves the input byte-for-byte as it was.
cp "$FIX/restricted.pdf" "$TMP/r-inplace.pdf"
expect_code 2 "$PDFUTIL" pages --delete 1 "$TMP/r-inplace.pdf"
expect_ok cmp -s "$FIX/restricted.pdf" "$TMP/r-inplace.pdf"

# The owner password lifts the restrictions, and the pages really go.
expect_ok "$PDFUTIL" pages --delete 1 --password owner -o "$TMP/r-owner.pdf" "$FIX/restricted.pdf"
expect_grep "pages: 4" "$PDFUTIL" info "$TMP/r-owner.pdf"
# A wrong one does not.
expect_code 2 "$PDFUTIL" pages --delete 1 --password wrong -o "$TMP/r-wrong.pdf" "$FIX/restricted.pdf"

# Edits PDFKit does not restrict still work, and so does building a new document.
expect_ok "$PDFUTIL" crop --margins 10,10,10,10 -o "$TMP/r-crop.pdf" "$FIX/restricted.pdf"
expect_ok "$PDFUTIL" pages --extract 2-3 -o "$TMP/r-ext.pdf" "$FIX/restricted.pdf"
expect_grep "pages: 2" "$PDFUTIL" info "$TMP/r-ext.pdf"

# decrypt needs no password to remove the restrictions, after which the delete
# goes through. An explicit empty password works the same.
expect_ok "$PDFUTIL" decrypt -o "$TMP/r-dec.pdf" "$FIX/restricted.pdf"
expect_nogrep "Encrypt" sh -c 'LC_ALL=C grep -ao "/Encrypt" "$1"' _ "$TMP/r-dec.pdf"
expect_ok "$PDFUTIL" decrypt --password '' -o "$TMP/r-dec-empty.pdf" "$FIX/restricted.pdf"
expect_ok "$PDFUTIL" pages --delete 1 -o "$TMP/r-dec-del.pdf" "$TMP/r-dec.pdf"
expect_grep "pages: 4" "$PDFUTIL" info "$TMP/r-dec-del.pdf"

# odd-permissions.pdf allows everything, but its /P is stored as a positive
# number. The fixture itself must open, or every check below is vacuous.
expect_grep "locked: false" "$PDFUTIL" info "$FIX/odd-permissions.pdf"
expect_grep "PAGE-2-MARKER" "$PDFUTIL" text -p 2 "$FIX/odd-permissions.pdf"

# A PDFKit re-save of it no longer opens, so the save is refused and nothing
# is written - whichever edit triggered it.
expect_code 2 "$PDFUTIL" rotate 90 -o "$TMP/odd-rot.pdf" "$FIX/odd-permissions.pdf"
expect_grep "does not open with the original's password" sh -c '"$1" rotate 90 -o "$2" "$3" 2>&1' _ "$PDFUTIL" "$TMP/odd-rot.pdf" "$FIX/odd-permissions.pdf"
expect_code 2 "$PDFUTIL" pages --delete 1 -o "$TMP/odd-del.pdf" "$FIX/odd-permissions.pdf"
expect_code 2 "$PDFUTIL" crop --margins 10,10,10,10 -o "$TMP/odd-crop.pdf" "$FIX/odd-permissions.pdf"
for refused in odd-rot odd-del odd-crop; do
    if [ -e "$TMP/$refused.pdf" ]; then fail "$refused: a refused save still wrote $TMP/$refused.pdf"; fi
done
cp "$FIX/odd-permissions.pdf" "$TMP/odd-inplace.pdf"
expect_code 2 "$PDFUTIL" rotate 90 "$TMP/odd-inplace.pdf"
expect_ok cmp -s "$FIX/odd-permissions.pdf" "$TMP/odd-inplace.pdf"

# A new document carries no protection, so extract and decrypt still deliver,
# and the decrypted copy can then be edited.
expect_ok "$PDFUTIL" pages --extract 2-3 -o "$TMP/odd-ext.pdf" "$FIX/odd-permissions.pdf"
expect_grep "pages: 2" "$PDFUTIL" info "$TMP/odd-ext.pdf"
expect_ok "$PDFUTIL" decrypt -o "$TMP/odd-dec.pdf" "$FIX/odd-permissions.pdf"
expect_ok "$PDFUTIL" rotate 90 -o "$TMP/odd-dec-rot.pdf" "$TMP/odd-dec.pdf"
expect_grep "rotation 90" "$PDFUTIL" info "$TMP/odd-dec-rot.pdf"

# A PDF that needs its password still saves: the written copy opens with that
# same password, which is what the save check asks.
expect_ok "$PDFUTIL" rotate 90 --password test -o "$TMP/locked-rot.pdf" "$FIX/locked.pdf"
expect_code 2 "$PDFUTIL" info "$TMP/locked-rot.pdf"
expect_grep "rotation 90" "$PDFUTIL" info --password test "$TMP/locked-rot.pdf"
