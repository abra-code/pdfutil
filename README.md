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
| `text` | Extract the text layer as UTF-8 (to stdout or an `-o` file) |

Run `pdfutil <verb> --help` for a specific verb's options.
