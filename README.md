# pdfutil

A single, zero-dependency macOS command-line tool for working with PDFs, built
only on system frameworks (PDFKit, CoreGraphics, Quartz, ImageIO, Vision). No
third-party libraries and no package manager: one universal (arm64 + x86_64)
binary produced by a plain `swiftc` invocation.

## Build

    ./build.sh        # produces build/pdfutil (universal, ad-hoc signed)
    ./build.sh arm64  # single-architecture build (arm64 or x86_64)
    ./test.sh         # builds, generates fixtures, runs the smoke tests

Deployment target: macOS 14.0.

## Usage

    pdfutil <verb> [options] <input...>

Diagnostics go to stderr; payload (text, JSON) goes to stdout. Exit status is
0 on success, 1 on a usage/argument error, and 2 on a processing failure.

Page ranges (`-p/--pages`) are qpdf-style, 1-based and inclusive: `1-5,9,12-end`,
where `end` is the last page and `all` is every page. Descending terms (`5-2`)
and repeats are allowed.

## Verbs

| Verb | Description |
| --- | --- |
| `info` | Report version, page count, geometry, security, metadata, outline (`--json`) |
| `text` | Extract the text layer as UTF-8 (to stdout or an `-o` file) |
| `search` | Find a string; print page + snippet, or `--count` / `--json` |
| `outline` | Print the table of contents (indented or `--json`) |
| `merge` | Concatenate PDFs into one, with optional per-input ranges |
| `split` | Split into parts by page count (`--every`) or `--chapters` |
| `pages` | Extract/reorder (`--extract`) or delete (`--delete`) pages |
| `rotate` | Rotate pages by 90/180/270/-90, lossless |
| `crop` | Set a page box by `--rect` or `--margins` |
| `metadata` | Read/`--set`/`--delete`/`--strip` Info-dictionary attributes |
| `render` | Rasterize pages to PNG/JPEG/TIFF/HEIC at a DPI or scale |
| `frompages` | Build a PDF from images and/or PDFs (img2pdf, mixed inputs) |
| `encrypt` | Add a user/owner password and permission flags (`--allow`) |
| `decrypt` | Remove password protection (re-save unencrypted); `--password ''` removes the permission restrictions of a PDF that opens without a password |
| `flatten` | Burn annotations and form fields into the page content |
| `reduce` | Recompress/downsample images to shrink a PDF (redraw) |
| `ocr` | Recognize text via Vision; print it or embed a searchable layer |
| `forms` | List, `--fill` (from JSON), or `--flatten` AcroForm fields |
| `watermark` | Stamp a text/image mark (burn-in) or a freeText annotation |
| `linearize` | Rewrite in linearized "fast web view" form (redraw) |
| `pdfa` | Rewrite as PDF/A-2B for archival (redraw) |
| `mcp` | Run an MCP server over stdio (`--root PATH`, `--writable`) |

Run `pdfutil <verb> --help` for a specific verb's options.

## MCP server mode

`pdfutil mcp --root PATH [--root PATH]...` runs a read-only Model Context
Protocol server over stdio (newline-delimited JSON-RPC 2.0). It exposes the
read tools - `pdf_info`, `pdf_text`, `pdf_search`, `pdf_outline`, `pdf_render`,
`pdf_ocr`, `pdf_forms_list`, `pdf_list` - each confined to the `--root` paths
(a root may be a directory or a single PDF file). Adding `--writable` also
serves the mutating tools (`pdf_merge`, `pdf_extract_pages`,
`pdf_delete_pages`, `pdf_rotate`, `pdf_metadata_set`, `pdf_forms_fill`,
`pdf_watermark`, `pdf_reduce`, `pdf_render_to_file`) with create-only outputs:
every result is a new file under a root, and an output path that already exists
is refused, so no existing file can ever be modified or destroyed through the
server. The server writes files but never creates directories - an output whose
parent directory is missing is refused rather than made. See
[docs/mcp-tools.md](docs/mcp-tools.md) for the tool schemas and the full
safety model.

Client configuration (e.g. an MCP `mcpServers` entry; point `--root` at a
narrow working folder, not a broad tree like `~/Documents`):

```json
{
  "mcpServers": {
    "pdfutil": {
      "command": "/usr/local/bin/pdfutil",
      "args": ["mcp", "--root", "/Users/me/PDFWork", "--writable"]
    }
  }
}
```
