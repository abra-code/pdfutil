# mcp --writable - the mutating tier, Part B: forms fill, watermark, reduce.

MCP_FIX="$PWD/$FIX"
WROOTB="$PWD/$TMP/mcp-write-b"
mkdir -p "$WROOTB"

# A 1x1 PNG for the image-watermark path (an input under a root like any other).
python3 -c "import base64,sys;open(sys.argv[1],'wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))" "$WROOTB/mark.png"

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_forms_fill\",\"arguments\":{\"path\":\"$MCP_FIX/form.pdf\",\"fields\":{\"name\":\"Bob\",\"agree\":true},\"output\":\"$WROOTB/filled.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_forms_list\",\"arguments\":{\"path\":\"$WROOTB/filled.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_forms_fill\",\"arguments\":{\"path\":\"$MCP_FIX/form.pdf\",\"fields\":{\"name\":\"Bob\"},\"flatten\":true,\"output\":\"$WROOTB/flat.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_forms_list\",\"arguments\":{\"path\":\"$WROOTB/flat.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_watermark\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"text\":\"DRAFT\",\"annotation\":true,\"output\":\"$WROOTB/wm-ann.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_info\",\"arguments\":{\"path\":\"$WROOTB/wm-ann.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_watermark\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"text\":\"CONFIDENTIAL\",\"opacity\":0.5,\"pages\":\"1-2\",\"output\":\"$WROOTB/wm-burn.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_reduce\",\"arguments\":{\"path\":\"$MCP_FIX/image.pdf\",\"quality\":60,\"dpi\":72,\"output\":\"$WROOTB/reduced.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_watermark\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"text\":\"X\",\"imagePath\":\"$MCP_FIX/image.pdf\",\"output\":\"$WROOTB/both.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_forms_fill\",\"arguments\":{\"path\":\"$MCP_FIX/form.pdf\",\"fields\":{\"nope\":\"x\"},\"output\":\"$WROOTB/badfield.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_watermark\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"imagePath\":\"/etc/passwd\",\"output\":\"$WROOTB/badimg.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_reduce\",\"arguments\":{\"path\":\"$MCP_FIX/image.pdf\",\"quality\":0,\"output\":\"$WROOTB/badq.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_watermark\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"imagePath\":\"$WROOTB/mark.png\",\"output\":\"$WROOTB/wm-img.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_watermark\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"text\":\"D\",\"annotation\":\"true\",\"output\":\"$WROOTB/badann.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_watermark\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"imagePath\":\"$WROOTB/mark.png\",\"annotation\":true,\"output\":\"$WROOTB/badann2.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":17,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_reduce\",\"arguments\":{\"path\":\"$MCP_FIX/image.pdf\",\"gray\":true,\"quality\":50,\"output\":\"$WROOTB/badgray.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":18,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_forms_fill\",\"arguments\":{\"path\":\"$MCP_FIX/form.pdf\",\"fields\":{\"agree\":1},\"output\":\"$WROOTB/badbool.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":19,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_watermark\",\"arguments\":{\"path\":\"$MCP_FIX/text.pdf\",\"text\":\"D\",\"annotation\":true,\"angle\":30,\"output\":\"$WROOTB/badangle.pdf\"}}}" \
  | "$PDFUTIL" mcp --root "$MCP_FIX" --root "$WROOTB" --writable > "$TMP/mcpw-b.txt" 2>/dev/null

python3 - "$TMP/mcpw-b.txt" "$MCP_FIX/image.pdf" <<'PY' || fail "mcp-write-b session assertions failed"
import sys, json, os

resp = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        m = json.loads(line)
        if "id" in m:
            resp[m["id"]] = m

ok = True
def check(cond, msg):
    global ok
    if not cond:
        ok = False
        print("MCP-WRITE-B FAIL:", msg)

def text(i):
    return resp[i]["result"]["content"][0]["text"]

def is_error(i):
    return resp[i]["result"].get("isError") is True

filled = json.loads(text(2))
check(filled["pageCount"] == 1 and filled["bytes"] > 0, "pdf_forms_fill result JSON")
fields = {f["name"]: f["value"] for f in json.loads(text(3))}
check(fields.get("name") == "Bob" and fields.get("agree") == "on", "the filled output carries the values")
check(json.loads(text(5)) == [], "flatten drops the interactive fields")

check(json.loads(text(6))["pageCount"] == 5, "annotation watermark keeps 5 pages")
info = json.loads(text(7))
check(all(p["annotations"] >= 1 for p in info["pages"]), "every page got the watermark annotation")

check(json.loads(text(8))["pageCount"] == 5, "burn-in watermark keeps 5 pages")

reduced = json.loads(text(9))
check(reduced["pageCount"] == 2, "reduce keeps 2 pages")
check(0 < reduced["bytes"] < os.path.getsize(sys.argv[2]), "reduce made the scan fixture smaller")

check(is_error(10) and "exactly one" in text(10), "text+imagePath together refused")
check(is_error(11) and "unknown field" in text(11), "an unknown form field is a tool error")
check(is_error(12) and "outside allowed roots" in text(12), "a watermark image outside the roots refused")
check(is_error(13) and "quality" in text(13), "quality 0 refused")

check(json.loads(text(14))["pageCount"] == 5, "image watermark writes 5 pages")
check(is_error(15) and "true or false" in text(15), "a string 'true' for annotation is refused, not dropped")
check(is_error(16) and "requires 'text'" in text(16), "annotation with an image is refused")
check(is_error(17) and "gray" in text(17), "gray combined with quality is refused")
check(is_error(18) and "true or false" in text(18), "a numeric checkbox value is refused")
# The schema has always said "burn-in only"; watermarkAnnotation never read
# rotateMark, so the angle was accepted and dropped rather than enforced.
check(is_error(19) and "burn-in only" in text(19), "angle combined with annotation is refused")

sys.exit(0 if ok else 1)
PY

# No refused call left an output behind.
for f in both badfield badimg badq badann badann2 badgray badbool badangle; do
    if [ -e "$WROOTB/$f.pdf" ]; then fail "a refused call left $f.pdf behind"; fi
done
