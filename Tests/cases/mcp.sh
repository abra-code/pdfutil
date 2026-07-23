# mcp verb - a scripted stdio JSON-RPC session against the read-only server.

MCP_ROOT="$PWD/$FIX"

# A usage error when no --root is given.
expect_code 1 "$PDFUTIL" mcp

# Drive a full session: initialize, the initialized notification, tools/list, a
# tool call, an out-of-root call, and an unknown method.
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_text\",\"arguments\":{\"path\":\"$MCP_ROOT/text.pdf\",\"pages\":\"3\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_info\",\"arguments\":{\"path\":\"$MCP_ROOT/text.pdf\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_search\",\"arguments\":{\"path\":\"$MCP_ROOT/text.pdf\",\"query\":\"needle\"}}}" \
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"pdf_outline","arguments":{"path":"/etc/passwd"}}}' \
  '{"jsonrpc":"2.0","id":7,"method":"no_such_method"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_text\",\"arguments\":{\"path\":\"$MCP_ROOT/locked.pdf\",\"password\":\"test\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"pdf_text\",\"arguments\":{\"path\":\"$MCP_ROOT/locked.pdf\"}}}" \
  | "$PDFUTIL" mcp --root "$MCP_ROOT" > "$TMP/mcp-out.txt" 2>/dev/null

python3 - "$TMP/mcp-out.txt" <<'PY' || fail "mcp session assertions failed"
import sys, json
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

check(resp[1]["result"]["protocolVersion"] == "2025-06-18", "initialize echoes protocolVersion")
check(resp[1]["result"]["serverInfo"]["name"] == "pdfutil", "serverInfo name")
names = [t["name"] for t in resp[2]["result"]["tools"]]
check("pdf_text" in names and "pdf_info" in names, "tools/list advertises the text tools")
schemas = json.dumps([t["inputSchema"] for t in resp[2]["result"]["tools"]])
check("password" not in schemas, "no tool schema advertises a password parameter")
check("PAGE-3-MARKER" in resp[3]["result"]["content"][0]["text"], "pdf_text returns page 3 text")
check('"pageCount" : 5' in resp[4]["result"]["content"][0]["text"], "pdf_info reports 5 pages")
check("needle" in resp[5]["result"]["content"][0]["text"], "pdf_search finds needle")
check(resp[6]["result"].get("isError") is True, "out-of-root path refused")
check(resp[7]["error"]["code"] == -32601, "unknown method -> -32601")
check(resp[8]["result"].get("isError") is True
      and "password" in resp[8]["result"]["content"][0]["text"],
      "supplying a password is refused with the policy error")
check(resp[9]["result"].get("isError") is True
      and "password-protected" in resp[9]["result"]["content"][0]["text"],
      "a locked PDF without a password reports itself")
check(set(resp.keys()) == {1, 2, 3, 4, 5, 6, 7, 8, 9}, "the notification produced no response")
sys.exit(0 if ok else 1)
PY
