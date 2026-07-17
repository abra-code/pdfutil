# mcp binary tools - pdf_render (PNG image content), pdf_ocr, pdf_forms_list.

MCP_ROOT="$PWD/$FIX"

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render\",\"arguments\":{\"path\":\"$MCP_ROOT/text.pdf\",\"page\":1,\"dpi\":72}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_forms_list\",\"arguments\":{\"path\":\"$MCP_ROOT/form.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_ocr\",\"arguments\":{\"path\":\"$MCP_ROOT/image.pdf\",\"pages\":\"1\"}}}" \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"pdf_render","arguments":{"path":"/etc/hosts","page":1}}}' \
  | "$PDFUTIL" mcp --root "$MCP_ROOT" > "$TMP/mcp-bin-out.txt" 2>/dev/null

python3 - "$TMP/mcp-bin-out.txt" <<'PY' || fail "mcp binary-tool assertions failed"
import sys, json, base64
resp = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    m = json.loads(line)
    if "id" in m:
        resp[m["id"]] = m

ok = True
def check(cond, msg):
    global ok
    if not cond:
        ok = False
        print("MCP FAIL:", msg)

img = resp[2]["result"]["content"][0]
check(img["type"] == "image", "pdf_render returns an image content item")
check(img["mimeType"] == "image/png", "pdf_render mimeType is image/png")
raw = base64.b64decode(img["data"])
check(raw[:8] == b"\x89PNG\r\n\x1a\n", "pdf_render data is valid PNG (magic bytes)")
check('"name"' in resp[3]["result"]["content"][0]["text"], "pdf_forms_list mentions the name field")
check("OCRTEST" in resp[4]["result"]["content"][0]["text"], "pdf_ocr recovers OCRTEST")
check(resp[5]["result"].get("isError") is True, "pdf_render refuses an out-of-root path")
sys.exit(0 if ok else 1)
PY
