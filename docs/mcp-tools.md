# pdfutil MCP tools

`pdfutil mcp --root DIR [--root DIR]...` runs a read-only Model Context Protocol
server over stdio (newline-delimited JSON-RPC 2.0, one object per line). It
exposes the tools below. Every tool is read-only; every `path` must resolve
(after symlink canonicalization) under one of the `--root` directories, or the
call returns a tool error.

A tool result is an MCP `content` array. Text tools return a single `text` item;
`pdf_render` returns an `image` item. A tool-level failure sets
`result.isError = true` with a `text` item describing it (JSON-RPC errors are
reserved for protocol problems: `-32700` parse, `-32600` invalid request,
`-32601` method not found).

Caps: `pdf_text` and `pdf_ocr` cap their output at 50000 characters (narrow with
`pages`); `pdf_render` caps `dpi` at 300.

Encrypted PDFs: no tool accepts a password, by design - passwords must not
travel through the agent (they would sit in model context and host logs in
clear text). A call that supplies a `password` argument is refused with a tool
error, and a password-protected file reports itself as such. Decrypt first with
the pdfutil CLI (`pdfutil decrypt --password-stdin`), which keeps the password
out of the agent loop.

---

## `pdf_info`

```json
{
  "path": "<string>"   // required; a PDF under an allowed root
}
```

**Response:** a `text` item with the info JSON (version, pageCount, encrypted,
permissions, metadata, outlineItems, and per-page geometry incl. annotation
count).

---

## `pdf_text`

```json
{
  "path":  "<string>",   // required
  "pages": "<string>"    // optional page range, e.g. "1-5,9" (1-based); default all
}
```

**Response:** a `text` item with the extracted text layer. Over 50000 characters
returns an `isError` item asking to narrow `pages`.

---

## `pdf_search`

```json
{
  "path":          "<string>",   // required
  "query":         "<string>",   // required; text to find
  "pages":         "<string>",   // optional page range; default all
  "maxResults":    <integer>,    // optional; default 50
  "caseSensitive": <boolean>     // optional; default false
}
```

**Response:** a `text` item with a JSON array of matches `{page, snippet,
bounds}`. When more than `maxResults` matched, a trailing note reports the total.

---

## `pdf_outline`

```json
{
  "path": "<string>"   // required
}
```

**Response:** a `text` item with the outline as a nested JSON tree `{label, page,
children}`, or `(no outline)`.

---

## `pdf_render`

```json
{
  "path": "<string>",   // required
  "page": <integer>,    // required; a single 1-based page number
  "dpi":  <integer>     // optional; default 150, capped at 300
}
```

**Response:** an `image` content item `{type:"image", data:"<base64>",
mimeType:"image/png"}`.

---

## `pdf_ocr`

```json
{
  "path":      "<string>",           // required
  "pages":     "<string>",           // optional page range; default all
  "languages": ["<string>", ...]     // optional BCP-47 tags (e.g. "en-US"); omit to auto-detect
}
```

**Response:** a `text` item with the Vision-recognized text (each page is
rasterized at 300 dpi). Over 50000 characters returns an `isError` item.

---

## `pdf_forms_list`

```json
{
  "path": "<string>"   // required
}
```

**Response:** a `text` item with a JSON array of form fields `{page, name, kind,
value, choices?, readOnly}`.

---

## Example session

```
--> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}
<-- {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"pdfutil","version":"0.1"}}}
--> {"jsonrpc":"2.0","method":"notifications/initialized"}
--> {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pdf_text","arguments":{"path":"/docs/report.pdf","pages":"1-2"}}}
<-- {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"..."}]}}
```
