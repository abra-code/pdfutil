# pdfutil MCP tools

`pdfutil mcp --root PATH [--root PATH]... [--writable]` runs a Model Context
Protocol server over stdio (newline-delimited JSON-RPC 2.0, one object per
line). Every `path` must resolve (after symlink canonicalization) under one of
the `--root` paths, or the call returns a tool error. A `--root` may be a
directory, or a single PDF file - a file root allows exactly that file (least
privilege for a one-document session) and can never host outputs.

Without `--writable` the server is read-only: only the read tools below are
advertised and dispatchable. With `--writable` the same roots become writable
and the mutating tools are added - but only through create-only outputs (see
"Mutating tools").

Root scoping advice: point `--root` at a narrow, purpose-made working folder
(e.g. `~/PDFWork`) and drop files into it per task - never at a broad tree like
`~/Documents`, since everything under a root is readable to the agent. Use a
file root when even a folder is too broad.

A tool result is an MCP `content` array. Text tools return a single `text` item;
`pdf_render` returns an `image` item. A tool-level failure sets
`result.isError = true` with a `text` item describing it (JSON-RPC errors are
reserved for protocol problems: `-32700` parse, `-32600` invalid request,
`-32601` method not found).

Every tool definition carries MCP tool annotations: the read tools declare
`readOnlyHint: true`; the mutating tools declare `readOnlyHint: false,
destructiveHint: false, idempotentHint: false`. `destructiveHint: false` is
honest and load-bearing: because outputs are create-only, a mutating tool can
add files but never alter or destroy existing data.

Caps: `pdf_text` and `pdf_ocr` cap their output at 50000 characters (narrow with
`pages`); `pdf_render` caps `dpi` at 300.

Strict arguments: every schema is closed (`additionalProperties: false`) and the
server independently refuses any argument a tool does not declare, since a
client is not obliged to validate. A wrong-typed value is refused the same way.
Nothing is silently dropped: an ignored argument would make a tool do something
the agent did not ask for, and - worse - let a call report success for work it
never performed (an agent passing `output` to a read tool and believing a file
was written).

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

The PNG comes back inline. `pdf_render` writes no file and has no `output`
parameter - passing one is refused, not ignored. To save a PNG to disk, use the
`pdfutil render -o` CLI.

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

## `pdf_list`

```json
{
  "root":      "<string>",   // optional; list only under this path (must be within a root); default all roots
  "recursive": <boolean>     // optional; default true
}
```

**Response:** a `text` item with a JSON array of `{path, bytes, pageCount}` for
every PDF under the roots (`pageCount` is `null` for an encrypted or unreadable
file; a file root lists itself). Hidden files and anything inside a hidden
directory are skipped. Capped at 500 entries with a truncation note. This is
the discovery tool that makes multi-document workflows possible in hosts
without a shell.

---

## Mutating tools (`--writable`)

Starting the server with `--writable` adds nine mutating tools. The safety
model, in the order it protects you:

1. **Launch-time opt-in.** Without `--writable` the mutating tools are not
   advertised and not dispatchable - a server started without the flag is
   exactly as read-only as before the flag existed.
2. **Create-only outputs.** Every mutating tool writes a **new** file at the
   explicit `output` path. The path must sit under a `--root`, its parent
   directory must exist, and nothing may already exist at it (a pre-planted
   symlink counts as existing). There is no overwrite parameter and no MCP
   equivalent of `--force`, so no pre-existing file can ever be modified or
   deleted through the server. Writes are temp-file + atomic move, and the
   move fails rather than replacing anything that appears concurrently.
3. **Files, never directories.** The server creates files only. The parent
   directory of an `output` must already exist; a missing one is a tool error,
   never an implicit `mkdir -p`. See "Directory policy" below.
4. **Host prompts.** The annotations above tell a conforming host to gate the
   mutating tools harder than the read tools.

This guarantee is promise and code correctness, not kernel sandboxing: the
process is not otherwise confined.

The one residual write risk is unbounded creation: nothing existing can
change, but every call adds a new file and there is no delete tool, so a
looping agent can fill the working folder (and, eventually, the volume) with
outputs. Point the roots at a dedicated folder you empty yourself.

### Directory policy

**The server creates files, never directories.** The parent directory of every
`output` must already exist. A call naming a missing directory - say
`.../PDFWork/temp/page1.png` when `temp/` does not exist - is refused with

```
output directory does not exist: /.../PDFWork/temp - this server writes files
but never creates directories; write to a directory that already exists, or ask
the user to create that one
```

Nothing is written, and no directory is created. There is no `mkdir` parameter
and no tool that makes one. The reasons:

- **The root check needs an existing parent.** A path is admitted by
  canonicalizing its parent (`resolvingSymlinksInPath` realpaths only components
  that exist) and testing *that* against the roots. With an existing parent the
  real location is known exactly - symlinks and `..` resolved - before anything
  is written. Creating the missing components first would mean admitting a path
  whose true location is unknowable until after the directories exist, which is
  where sandbox escapes come from.
- **A typo should cost an error, not a mess.** An agent that mistypes a path
  gets one refusal, not a tree of stray directories under the user's root.

So the write contract is exactly: *one call creates one new file, in a directory
you already made.* Create the folders you want the agent to use when you set up
the root; the agent fills them.

Results: every mutating tool returns a `text` item with
`{"output": "<path>", "bytes": <n>, "pageCount": <n>}` so the agent can chain
the next call (the output is immediately readable through the same server).
`pdf_render_to_file` writes an image rather than a PDF, so it returns
`{"output", "bytes", "format", "width", "height", "dpi"}` instead.

In-place editing, overwriting, encryption changes (`encrypt`/`decrypt`), and
multi-file outputs (`split`) stay CLI-only. Encryption is excluded
deliberately: passwords must not travel through the agent.

### `pdf_merge`

```json
{
  "inputs": [                      // required; at least two, concatenated in order
    { "path": "<string>",          //   a PDF under a root
      "pages": "<string>" },       //   optional page range from that input
    ...
  ],
  "output": "<string>"             // required; new file under a root
}
```

Structure-preserving: annotations, links, and form fields survive.

### `pdf_extract_pages`

```json
{
  "path":   "<string>",   // required
  "pages":  "<string>",   // required; kept in the listed order, repeats allowed (e.g. "3,1,2")
  "output": "<string>"    // required
}
```

Page-level structure survives; the document outline is not carried.

### `pdf_delete_pages`

```json
{
  "path":   "<string>",   // required
  "pages":  "<string>",   // required; pages to remove
  "output": "<string>"    // required
}
```

Structure-preserving; the outline is kept (destinations to removed pages may
dangle). Deleting every page is refused.

### `pdf_rotate`

```json
{
  "path":   "<string>",   // required
  "angle":  <integer>,    // required; 90, 180, 270, or -90 (added to the current rotation)
  "pages":  "<string>",   // optional; default all
  "output": "<string>"    // required
}
```

Lossless: only the page rotation entry changes.

### `pdf_metadata_set`

```json
{
  "path":   "<string>",              // required
  "set":    { "<key>": "<value>" },  // attributes to set (string values)
  "delete": ["<key>", ...],          // attributes to remove
  "output": "<string>"               // required; at least one of set/delete
}
```

Keys: `title`, `author`, `subject`, `keywords` (comma-separated), `creator`,
`producer`, `creation-date`, `modification-date` (ISO 8601).
Structure-preserving.

### `pdf_forms_fill`

```json
{
  "path":    "<string>",             // required
  "fields":  { "<name>": <value> },  // required; string for text/choice, boolean for a checkbox
  "flatten": <boolean>,              // optional; default false
  "output":  "<string>"              // required
}
```

Structure-preserving; with `flatten` the values burn into the page content and
the interactive fields are dropped. Unknown field names are a tool error that
lists the available names (use `pdf_forms_list` first).

### `pdf_watermark`

```json
{
  "path":       "<string>",   // required
  "text":       "<string>",   // exactly one of text / imagePath
  "imagePath":  "<string>",   // an image under a root (sandbox-checked input)
  "position":   "<string>",   // optional; center (default), top-left, top-right, bottom-left, bottom-right
  "angle":      <number>,     // optional; mark rotation in degrees, burn-in only (default 45).
                              //   Refused with annotation: true, not ignored.
  "opacity":    <number>,     // optional; 0-1 (default 0.25)
  "pages":      "<string>",   // optional; default all
  "annotation": <boolean>,    // optional; default false
  "output":     "<string>"    // required
}
```

The default burn-in **redraws** the document: the output loses annotations,
links, outline, and form fields. `annotation: true` is structure-preserving
(text only, axis-aligned).

### `pdf_reduce`

```json
{
  "path":    "<string>",   // required
  "quality": <integer>,    // optional; JPEG quality 1-100 (default 85)
  "dpi":     <integer>,    // optional; downsample images above this DPI, 0 disables (default 150)
  "gray":    <boolean>,    // optional; default false, exclusive with quality/dpi
  "output":  "<string>"    // required
}
```

**Redraws** the document: the output loses annotations, links, outline, and
form fields. `gray` applies the system Gray Tone filter *instead of* the
recompress/downsample filter, so combining it with `quality` or `dpi` is
refused.

---

### `pdf_render_to_file`

```json
{
  "path":        "<string>",   // required
  "page":        <integer>,    // required; a single 1-based page number
  "output":      "<string>",   // required; extension selects the format
  "dpi":         <integer>,    // optional; default 150, clamped to 600
  "quality":     <integer>,    // optional; 1-100 for .jpg/.heic (default 85)
  "transparent": <boolean>     // optional; default false, not for .jpg
}
```

The write-tier counterpart of [`pdf_render`](#pdf_render): it saves an image to
disk instead of returning one inline. Use `pdf_render` when the agent needs to
*look* at a page, and this when a file must *exist*.

The `output` extension selects the format - `.png`, `.jpg`/`.jpeg`, `.tiff`/
`.tif`, or `.heic` - and any other extension is refused. There is deliberately
no `format` parameter: it could contradict the name on disk (`format: "png"`
writing to `page.jpg`), and that disagreement has no defensible resolution.

`quality` applies only to the lossy formats and is **refused**, not ignored, on
the others; `transparent` is refused for `.jpg`. `dpi` clamps to 600 - higher
than `pdf_render`'s 300 cap, since nothing here rides back in the model's
context, but still bounded so a mistyped `"dpi": 100000` cannot drive a
multi-gigabyte bitmap.

One call renders one page to one file. A page *range* would mean several output
files under prefix naming, and the create-only guarantee is exact only while one
call claims one path; use `pdfutil render` for bulk rasterization.

**Response:** `{"output", "bytes", "format", "width", "height", "dpi"}`.

---

## Example session

```
--> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}
<-- {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"pdfutil","version":"0.1"}}}
--> {"jsonrpc":"2.0","method":"notifications/initialized"}
--> {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pdf_text","arguments":{"path":"/docs/report.pdf","pages":"1-2"}}}
<-- {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"..."}]}}
```
