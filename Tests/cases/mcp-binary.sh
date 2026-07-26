# mcp binary tools - pdf_render (PNG image content), pdf_ocr, pdf_forms_list.

MCP_ROOT="$PWD/$FIX"

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render\",\"arguments\":{\"path\":\"$MCP_ROOT/text.pdf\",\"page\":1,\"dpi\":72}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_forms_list\",\"arguments\":{\"path\":\"$MCP_ROOT/form.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_ocr\",\"arguments\":{\"path\":\"$MCP_ROOT/image.pdf\",\"pages\":\"1\"}}}" \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"pdf_render","arguments":{"path":"/etc/hosts","page":1}}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_render\",\"arguments\":{\"path\":\"$MCP_ROOT/text.pdf\",\"page\":1,\"output\":\"$TMP/nope/page1.png\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_text\",\"arguments\":{\"path\":\"$MCP_ROOT/text.pdf\",\"bogus\":1,\"alsoBogus\":2}}}" \
  '{"jsonrpc":"2.0","id":8,"method":"tools/list","params":{}}' \
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

# An argument the tool does not declare must be refused, not silently dropped.
# pdf_render writes no file, so accepting an "output" path would report success
# for a file that was never written.
r6 = resp[6]["result"]
check(r6.get("isError") is True, "pdf_render refuses an undeclared 'output' argument")
check("output" in r6["content"][0]["text"], "the rejection names the offending argument")
r7 = resp[7]["result"]
check(r7.get("isError") is True, "pdf_text refuses undeclared arguments")
check("alsoBogus" in r7["content"][0]["text"] and "bogus" in r7["content"][0]["text"],
      "the rejection names every offending argument")

# Every advertised schema is closed, so a validating client refuses them too.
tools = resp[8]["result"]["tools"]
check(len(tools) > 0, "tools/list advertises tools")
for t in tools:
    check(t["inputSchema"].get("additionalProperties") is False,
          "%s schema is closed (additionalProperties: false)" % t["name"])
sys.exit(0 if ok else 1)
PY
