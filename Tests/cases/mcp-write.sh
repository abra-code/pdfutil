# mcp --writable - the mutating tier, Part A: create-only outputs under the
# roots, the pdf_list discovery tool, tool annotations, and file roots.

MCP_FIX="$PWD/$FIX"
WROOT="$PWD/$TMP/mcp-write"
mkdir -p "$WROOT"
cp "$FIX/text.pdf" "$WROOT/existing.pdf"
ln -s /nonexistent-target "$WROOT/planted.pdf"

# --- Session 1: a server WITHOUT --writable stays exactly as read-only as today.
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_merge\",\"arguments\":{\"inputs\":[{\"path\":\"$MCP_FIX/text.pdf\"},{\"path\":\"$MCP_FIX/outline.pdf\"}],\"output\":\"$WROOT/ro.pdf\"}}}" \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"pdf_list","arguments":{}}}' \
  | "$PDFUTIL" mcp --root "$MCP_FIX" > "$TMP/mcpw-ro.txt" 2>/dev/null

# --- Session 2: a --writable server serves the mutating tier (create-only).
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_merge\",\"arguments\":{\"inputs\":[{\"path\":\"$MCP_FIX/text.pdf\",\"pages\":\"1-2\"},{\"path\":\"$MCP_FIX/text.pdf\",\"pages\":\"4-5\"}],\"output\":\"$WROOT/merged.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_info\",\"arguments\":{\"path\":\"$WROOT/merged.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_extract_pages\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"pages\":\"2-3\",\"output\":\"$WROOT/extract.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_delete_pages\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"pages\":\"1\",\"output\":\"$WROOT/deleted.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_rotate\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"angle\":90,\"output\":\"$WROOT/rotated.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_metadata_set\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"set\":{\"title\":\"MCP Title\"},\"output\":\"$WROOT/meta.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_info\",\"arguments\":{\"path\":\"$WROOT/meta.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_list\",\"arguments\":{\"root\":\"$WROOT\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_merge\",\"arguments\":{\"inputs\":[{\"path\":\"$MCP_FIX/text.pdf\"},{\"path\":\"$MCP_FIX/outline.pdf\"}],\"output\":\"$WROOT/existing.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_rotate\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"angle\":90,\"output\":\"/etc/mcp-escape.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_rotate\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"angle\":90,\"output\":\"$WROOT/nodir/x.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_rotate\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"angle\":90,\"output\":\"$WROOT/../mcp-escape.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_rotate\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"angle\":90,\"output\":\"$WROOT/planted.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_merge\",\"arguments\":{\"inputs\":[{\"path\":\"$MCP_FIX/text.pdf\"},{\"path\":\"/etc/passwd\"}],\"output\":\"$WROOT/badinput.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":17,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_extract_pages\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"pages\":\"1\",\"output\":\"$MCP_FIX/text.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":18,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_metadata_set\",\"arguments\":{\"path\":\"$WROOT/meta.pdf\",\"delete\":[\"title\"],\"output\":\"$WROOT/meta2.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":19,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_info\",\"arguments\":{\"path\":\"$WROOT/meta2.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_rotate\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"angle\":90.7,\"output\":\"$WROOT/badangle.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_rotate\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"angle\":180,\"pages\":null,\"output\":\"$WROOT/nullok.pdf\"}}}" \
  | "$PDFUTIL" mcp --root "$MCP_FIX" --root "$WROOT" --writable > "$TMP/mcpw-w.txt" 2>/dev/null

# --- Session 3: a single-file root allows exactly that file and no sibling,
# and can never host an output (writable or not).
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_text\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"pages\":\"3\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_info\",\"arguments\":{\"path\":\"$MCP_FIX/outline.pdf\"}}}" \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"pdf_list","arguments":{}}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_rotate\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"angle\":90,\"output\":\"$MCP_FIX/fileroot-out.pdf\"}}}" \
  | "$PDFUTIL" mcp --root "$MCP_FIX/text.pdf" --writable > "$TMP/mcpw-file.txt" 2>/dev/null

python3 - "$TMP/mcpw-ro.txt" "$TMP/mcpw-w.txt" "$TMP/mcpw-file.txt" <<'PY' || fail "mcp-write session assertions failed"
import sys, json

def load(path):
    resp = {}
    for line in open(path):
        line = line.strip()
        if line:
            m = json.loads(line)
            if "id" in m:
                resp[m["id"]] = m
    return resp

ro, w, fr = load(sys.argv[1]), load(sys.argv[2]), load(sys.argv[3])

ok = True
def check(cond, msg):
    global ok
    if not cond:
        ok = False
        print("MCP-WRITE FAIL:", msg)

def text(resp, i):
    return resp[i]["result"]["content"][0]["text"]

def is_error(resp, i):
    return resp[i]["result"].get("isError") is True

MUTATING = {"pdf_merge", "pdf_extract_pages", "pdf_delete_pages",
            "pdf_rotate", "pdf_metadata_set", "pdf_forms_fill",
            "pdf_watermark", "pdf_reduce"}

# Session 1: read-only server.
ro_tools = {t["name"]: t for t in ro[2]["result"]["tools"]}
check(not (MUTATING & set(ro_tools)), "no mutating tool advertised without --writable")
check("pdf_list" in ro_tools, "pdf_list advertised on a read-only server")
check(ro_tools["pdf_info"]["annotations"]["readOnlyHint"] is True, "pdf_info readOnlyHint true")
check(is_error(ro, 3) and "unknown tool" in text(ro, 3), "pdf_merge unknown without --writable")
check("text.pdf" in text(ro, 4), "pdf_list finds the fixtures")

# Session 2: writable server, positive paths.
w_tools = {t["name"]: t for t in w[2]["result"]["tools"]}
check(MUTATING & set(w_tools) == {"pdf_merge", "pdf_extract_pages", "pdf_delete_pages", "pdf_rotate", "pdf_metadata_set"},
      "the Part A mutating tools are advertised with --writable")
check(w_tools["pdf_merge"]["annotations"]["readOnlyHint"] is False, "pdf_merge readOnlyHint false")
check(w_tools["pdf_merge"]["annotations"]["destructiveHint"] is False, "pdf_merge destructiveHint false")
check(w_tools["pdf_merge"]["annotations"]["openWorldHint"] is False, "pdf_merge openWorldHint false")
check(w_tools["pdf_info"]["annotations"]["readOnlyHint"] is True, "read tools stay readOnlyHint true")

merged = json.loads(text(w, 3))
check(merged["pageCount"] == 4 and merged["bytes"] > 0 and merged["output"].endswith("/merged.pdf"),
      "pdf_merge result JSON (4 pages)")
check('"pageCount" : 4' in text(w, 4), "the merged output is readable through the same server")
check(json.loads(text(w, 5))["pageCount"] == 2, "pdf_extract_pages 2-3 -> 2 pages")
check(json.loads(text(w, 6))["pageCount"] == 4, "pdf_delete_pages 1 -> 4 pages")
check(json.loads(text(w, 7))["pageCount"] == 5, "pdf_rotate keeps 5 pages")
check(json.loads(text(w, 8))["pageCount"] == 5, "pdf_metadata_set keeps 5 pages")
check('"title" : "MCP Title"' in text(w, 9), "pdf_info sees the new title")
listing = text(w, 10)
check("merged.pdf" in listing and "existing.pdf" in listing, "pdf_list sees the new outputs")
check("planted.pdf" not in listing, "pdf_list skips the dangling symlink")

# Session 2: the negatives that carry the safety model.
check(is_error(w, 11) and "output exists" in text(w, 11), "existing output refused")
check(is_error(w, 12) and "outside allowed roots" in text(w, 12), "output outside the roots refused")
check(is_error(w, 13) and "does not exist" in text(w, 13), "missing output directory refused")
check(is_error(w, 14) and "outside allowed roots" in text(w, 14), "traversal output refused")
check(is_error(w, 15) and "output exists" in text(w, 15), "pre-planted symlink output refused")
check(is_error(w, 16) and "outside allowed roots" in text(w, 16), "input outside the roots refused")
check(is_error(w, 17) and "output exists" in text(w, 17), "output equal to the input refused")

# Metadata delete, and strict argument typing.
check(json.loads(text(w, 18))["pageCount"] == 5, "pdf_metadata_set delete writes the output")
check("MCP Title" not in text(w, 19), "the deleted title is gone")
check(is_error(w, 20) and "integer" in text(w, 20), "a fractional angle is refused, not truncated")
check(json.loads(text(w, 21))["pageCount"] == 5, "a JSON null optional counts as absent, not a type error")

# Session 3: file root.
check("PAGE-3-MARKER" in text(fr, 2), "a file root serves exactly that file")
check(is_error(fr, 3) and "outside allowed roots" in text(fr, 3), "a sibling of the file root is refused")
check("text.pdf" in text(fr, 4), "pdf_list lists the file root itself")
check(is_error(fr, 5) and "outside allowed roots" in text(fr, 5), "a file root cannot host outputs")

sys.exit(0 if ok else 1)
PY

# The refused writes left nothing behind, and no temp files leaked.
if ! cmp -s "$FIX/text.pdf" "$WROOT/existing.pdf"; then fail "existing.pdf was modified by a refused write"; fi
if [ -e "$PWD/$TMP/mcp-escape.pdf" ]; then fail "traversal output escaped the roots"; fi
if [ -e "$MCP_FIX/fileroot-out.pdf" ]; then fail "an output appeared next to a file root"; fi
if ls "$WROOT"/.pdfutil-*.pdf >/dev/null 2>&1; then fail "temp files leaked into the write root"; fi

# The read-only mcp.sh session still passes with the new arg parsing.
expect_code 1 "$PDFUTIL" mcp --writable
