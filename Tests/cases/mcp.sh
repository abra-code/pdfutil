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

# Protocol negotiation. 2025-03-26 is deliberately unsupported - it is the only
# revision that requires accepting JSON-RPC batches, and 2025-06-18 removed the
# requirement again - so asking for it must yield the latest revision instead of an
# echo. Every malformed shape must fall back rather than error: the bundle's launch
# probe drops a server whose handshake fails.
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":3,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
  '{"jsonrpc":"2.0","id":4,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' \
  '{"jsonrpc":"2.0","id":5,"method":"initialize","params":{"protocolVersion":"2026-07-28"}}' \
  '{"jsonrpc":"2.0","id":6,"method":"initialize","params":{"protocolVersion":"nonsense"}}' \
  '{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":null}}' \
  '{"jsonrpc":"2.0","id":8,"method":"initialize","params":{"protocolVersion":7}}' \
  '{"jsonrpc":"2.0","id":9,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":10,"method":"initialize"}' \
  | "$PDFUTIL" mcp --root "$MCP_ROOT" > "$TMP/mcp-negotiate.txt" 2>/dev/null

python3 - "$TMP/mcp-negotiate.txt" <<'PY' || fail "mcp negotiation assertions failed"
import sys, json
LATEST = "2025-11-25"
resp = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        m = json.loads(line)
        resp[m["id"]] = m

ok = True
def check(cond, label):
    global ok
    print(("  PASS: " if cond else "  FAIL: ") + label)
    if not cond:
        ok = False

def version(i):
    return resp.get(i, {}).get("result", {}).get("protocolVersion")

def errored(i):
    return "error" in resp.get(i, {})

for i, want in ((1, "2025-11-25"), (2, "2025-06-18"), (3, "2024-11-05")):
    check(version(i) == want and not errored(i), f"supported revision {want} echoed verbatim")

check(version(4) == LATEST, "2025-03-26 (batching) answered with the latest, not echoed")
check(version(5) == LATEST, "newer-than-known 2026-07-28 falls back to the latest")
check(version(6) == LATEST, "unparseable revision falls back to the latest")

for i, label in ((7, "null"), (8, "numeric"), (9, "absent"), (10, "no params")):
    check(version(i) == LATEST and not errored(i),
          f"tolerant fallback: {label} protocolVersion -> latest, no error")

sys.exit(0 if ok else 1)
PY

# A top-level JSON-RPC array is rejected, and that is intentional rather than a gap:
# no supported revision requires batch receive. Pinned so re-adding 2025-03-26 to
# kSupportedProtocolVersions without a parser fails here.
printf '%s\n' '[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","id":2,"method":"ping"}]' \
  | "$PDFUTIL" mcp --root "$MCP_ROOT" > "$TMP/mcp-batch.txt" 2>/dev/null

python3 - "$TMP/mcp-batch.txt" <<'PY' || fail "mcp batch assertions failed"
import sys, json
lines = [l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
ok = True
def check(cond, label):
    global ok
    print(("  PASS: " if cond else "  FAIL: ") + label)
    if not cond:
        ok = False

check(len(lines) == 1, f"batch produces exactly one reply (got {len(lines)})")
check(lines and json.loads(lines[0]).get("error", {}).get("code") == -32600,
      "batch rejected with -32600 Invalid Request")
sys.exit(0 if ok else 1)
PY
