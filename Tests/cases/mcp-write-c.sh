# mcp --writable - the mutating tier, Part C: pdf_render_to_file (the write-tier
# counterpart of the inline pdf_render, which returns a PNG and writes nothing).

MCP_FIX="$PWD/$FIX"
WROOTC="$PWD/$TMP/mcp-write-c"
mkdir -p "$WROOTC"

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"output\":\"$WROOTC/page1.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"output\":\"$WROOTC/page1.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":2,\"dpi\":72,\"quality\":60,\"output\":\"$WROOTC/p2.jpg\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"output\":\"$WROOTC/bad.bmp\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"transparent\":true,\"output\":\"$WROOTC/badtr.jpg\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"quality\":50,\"output\":\"$WROOTC/badq.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":99,\"output\":\"$WROOTC/badpage.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"output\":\"/etc/badroot.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"output\":\"$WROOTC/nodir/badpath.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"dpi\":100000,\"output\":\"$WROOTC/capped.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"transparent\":true,\"output\":\"$WROOTC/clear.png\"}}}" \
  '{"jsonrpc":"2.0","id":13,"method":"tools/list","params":{}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"output\":\"$WROOTC/page1.png/nested.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"output\":\"$WROOTC/x.png\",\"format\":\"jpeg\"}}}" \
  | "$PDFUTIL" mcp --root "$MCP_FIX" --root "$WROOTC" --writable > "$TMP/mcpw-c.txt" 2>/dev/null

python3 - "$TMP/mcpw-c.txt" "$WROOTC" <<'PY' || fail "mcp-write-c session assertions failed"
import sys, json, os, struct

resp = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        m = json.loads(line)
        if "id" in m:
            resp[m["id"]] = m
wroot = sys.argv[2]

ok = True
def check(cond, msg):
    global ok
    if not cond:
        ok = False
        print("MCP-WRITE-C FAIL:", msg)

def text(i):
    return resp[i]["result"]["content"][0]["text"]

def is_error(i):
    return resp[i]["result"].get("isError") is True

# A real file on disk, not an inline payload.
r = json.loads(text(2))
check(r["format"] == "png" and r["dpi"] == 150, "pdf_render_to_file reports format and dpi")
check(r["width"] == 1275 and r["height"] == 1650, "150 dpi letter page is 1275x1650 px")
png = os.path.join(wroot, "page1.png")
check(os.path.getsize(png) == r["bytes"] > 0, "the reported byte count matches the file")
with open(png, "rb") as fh:
    head = fh.read(24)
check(head[:8] == b"\x89PNG\r\n\x1a\n", "the written file is a PNG")
check(struct.unpack(">II", head[16:24]) == (1275, 1650), "PNG header carries the reported size")

# Create-only: outputs never overwrite.
check(is_error(3) and "output exists" in text(3), "a second call to the same output is refused")
check(os.path.getsize(png) == r["bytes"], "the refused overwrite left the first file intact")

# The extension selects the format.
j = json.loads(text(4))
check(j["format"] == "jpeg" and j["dpi"] == 72, ".jpg output renders as JPEG")
with open(os.path.join(wroot, "p2.jpg"), "rb") as fh:
    check(fh.read(2) == b"\xff\xd8", "the written .jpg is a JPEG")

check(is_error(5) and "extension" in text(5), "an unknown output extension is refused")
check(is_error(6) and "transparent" in text(6), "transparent on a jpeg is refused")
check(is_error(7) and "quality" in text(7), "quality on a png is refused, not ignored")
check(is_error(8) and "out of range" in text(8), "an out-of-range page is refused")
check(is_error(9) and "outside allowed roots" in text(9), "an output outside the roots is refused")
# Directory policy: files are created, directories never are.
check(is_error(10) and "directory does not exist" in text(10),
      "an output in a missing directory is refused, not created")
check("never creates directories" in text(10),
      "the refusal states the directory policy so the agent can recover")
check(not os.path.exists(os.path.join(wroot, "nodir")),
      "the refused call did not create the missing directory")

# dpi clamps to the 600 cap rather than driving an enormous bitmap.
capped = json.loads(text(11))
check(capped["dpi"] == 600, "dpi clamps to the 600 cap")
check(capped["width"] == 5100 and capped["height"] == 6600, "the capped render is 600 dpi sized")

check(json.loads(text(12))["format"] == "png", "transparent png renders")

# The tool is advertised, and every schema stays closed.
tools = {t["name"]: t for t in resp[13]["result"]["tools"]}
check("pdf_render_to_file" in tools, "tools/list advertises pdf_render_to_file when writable")
check(tools["pdf_render_to_file"]["annotations"]["readOnlyHint"] is False,
      "pdf_render_to_file is annotated as not read-only")
check(tools["pdf_render_to_file"]["annotations"]["destructiveHint"] is False,
      "pdf_render_to_file is annotated non-destructive (create-only)")
for t in tools.values():
    check(t["inputSchema"].get("additionalProperties") is False,
          "%s schema is closed" % t["name"])

# A regular file standing in for a parent directory is a distinct refusal.
check(is_error(14) and "not a directory" in text(14),
      "an output under a regular file is refused as not-a-directory")
# There is no 'format' parameter; the extension decides, so naming one is a
# refusal rather than a silently ignored contradiction.
check(is_error(15) and "unknown parameter" in text(15),
      "pdf_render_to_file refuses an undeclared 'format' argument")
sys.exit(0 if ok else 1)
PY

# No refused call left an output behind.
for f in bad.bmp badtr.jpg badq.png badpage.png badpath.png x.png; do
    if [ -e "$WROOTC/$f" ]; then fail "a refused call left $f behind"; fi
done
if [ -e /etc/badroot.png ]; then fail "an out-of-root output escaped the sandbox"; fi
# The temp-then-move write leaves no stray temp files.
if ls "$WROOTC"/.pdfutil-* >/dev/null 2>&1; then fail "a temp file was left behind"; fi

# Without --writable the tool must not exist at all.
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render_to_file\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"page\":1,\"output\":\"$WROOTC/ro.png\"}}}" \
  '{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}' \
  | "$PDFUTIL" mcp --root "$MCP_FIX" --root "$WROOTC" > "$TMP/mcpw-c-ro.txt" 2>/dev/null

python3 - "$TMP/mcpw-c-ro.txt" <<'PY' || fail "pdf_render_to_file leaked onto a read-only server"
import sys, json
resp = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        m = json.loads(line)
        if "id" in m:
            resp[m["id"]] = m
ok = True
if resp[2]["result"].get("isError") is not True or "unknown tool" not in resp[2]["result"]["content"][0]["text"]:
    print("MCP-WRITE-C FAIL: a read-only server still ran pdf_render_to_file")
    ok = False
if any(t["name"] == "pdf_render_to_file" for t in resp[3]["result"]["tools"]):
    print("MCP-WRITE-C FAIL: a read-only server advertises pdf_render_to_file")
    ok = False
sys.exit(0 if ok else 1)
PY

if [ -e "$WROOTC/ro.png" ]; then fail "a read-only server wrote ro.png"; fi
