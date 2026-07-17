# pdfutil

A single, zero-dependency macOS command-line tool for working with PDFs, built
only on system frameworks (PDFKit, CoreGraphics, Quartz, ImageIO, Vision). No
third-party libraries and no package manager: one universal (arm64 + x86_64)
binary produced by a plain `swiftc` invocation.

## Build

    ./build.sh        # produces ./pdfutil (universal, ad-hoc signed)
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

Run `pdfutil <verb> --help` for a specific verb's options.
