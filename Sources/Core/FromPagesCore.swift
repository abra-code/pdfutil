// Core/FromPagesCore.swift - assemble images and/or PDFs into one PDF (the
// img2pdf role, plus mixed inputs). Images become one page each (sized from
// their pixel dimensions and DPI); PDF inputs are redrawn page by page.

import Foundation
import CoreGraphics
import ImageIO

// The named page sizes --page-size accepts, in points (72 per inch). The
// A-series values are the standard integer roundings of their millimetre
// definitions (A4 is 210x297 mm = 595.28x841.89 pt).
let namedPageSizes: [String: CGSize] = [
    "letter":  CGSize(width: 612, height: 792),
    "legal":   CGSize(width: 612, height: 1008),
    "tabloid": CGSize(width: 792, height: 1224),
    "a3":      CGSize(width: 842, height: 1191),
    "a4":      CGSize(width: 595, height: 842),
    "a5":      CGSize(width: 420, height: 595),
]

// Parse a --page-size value: a name from the table above, or explicit WxH in
// points ("612x792", decimals allowed).
func parsePageSize(_ raw: String) throws -> CGSize {
    let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
    if let named = namedPageSizes[key] { return named }

    let parts = key.split(separator: "x", omittingEmptySubsequences: false)
    if parts.count == 2,
       let w = Double(parts[0]), let h = Double(parts[1]),
       w > 0, h > 0, w.isFinite, h.isFinite {
        return CGSize(width: w, height: h)
    }
    let names = namedPageSizes.keys.sorted().joined(separator: ", ")
    throw PDFUtilError.usage("--page-size expects one of \(names), or WxH in points (got '\(raw)')")
}

// Combine the inputs, in order, into a single PDF written to `output`. Each input
// is classified by whether CoreGraphics opens it as a PDF; otherwise it is read
// as an image (multi-frame images contribute one page per frame).
//
// `pageSize` and `dpiOverride` are alternative ways to size IMAGE pages and the
// verb refuses both at once: with a page size each image is scaled to fit a
// fixed page, and without one the page is whatever the image's own resolution
// says it should be.
//
// Neither touches PDF inputs, which are redrawn at their own page sizes. That is
// deliberate - rescaling someone's existing pages is a different operation from
// laying out photos - but it means a mixed run with --page-size yields mixed
// page sizes, which the help text says out loud.
func combineToPDF(inputs: [String], output: String, dpiOverride: Double?,
                  pageSize: CGSize?, force: Bool) throws {
    let fm = FileManager.default
    let outURL = URL(fileURLWithPath: output).standardizedFileURL

    let outExists = fm.fileExists(atPath: outURL.path)
    if outExists && !force {
        throw PDFUtilError.processing("output exists: \(output) (use --force to overwrite)")
    }

    let tmpURL = outURL.deletingLastPathComponent()
        .appendingPathComponent(".pdfutil-" + UUID().uuidString + ".pdf")

    // Default context media box; each page sets its own box when it begins.
    var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let ctx = CGContext(tmpURL as CFURL, mediaBox: &defaultBox, nil) else {
        throw PDFUtilError.processing("cannot create output PDF: \(output)")
    }

    do {
        for path in inputs {
            guard fm.fileExists(atPath: path) else {
                throw PDFUtilError.processing("file not found: \(path)")
            }
            let url = URL(fileURLWithPath: path)
            // Classify by the file header first: calling CGPDFDocument on a
            // non-PDF makes CoreGraphics log a noisy "%PDF not found" error.
            if looksLikePDF(path) {
                guard let pdf = CGPDFDocument(url as CFURL), pdf.numberOfPages > 0 else {
                    throw PDFUtilError.processing("cannot read PDF: \(path)")
                }
                if pdf.isEncrypted && !pdf.isUnlocked {
                    throw PDFUtilError.processing("PDF is password-protected: \(path)")
                }
                for i in 1...pdf.numberOfPages {
                    try autoreleasepool {
                        guard let page = pdf.page(at: i) else {
                            throw PDFUtilError.processing("cannot read page \(i) of \(path)")
                        }
                        drawPDFPagePreservingBox(page, into: ctx)
                    }
                }
            } else {
                try addImagePages(path: path, into: ctx, dpiOverride: dpiOverride,
                                  pageSize: pageSize)
            }
        }
    } catch {
        ctx.closePDF()
        try? fm.removeItem(at: tmpURL)
        throw error
    }
    ctx.closePDF()

    do {
        if outExists {
            _ = try fm.replaceItemAt(outURL, withItemAt: tmpURL)
        } else {
            try fm.moveItem(at: tmpURL, to: outURL)
        }
    } catch {
        try? fm.removeItem(at: tmpURL)
        throw PDFUtilError.processing("cannot save output: \(output)")
    }
}

// Cheap PDF sniff: a PDF's "%PDF-" header appears within the first bytes. Used
// to avoid handing image files to CGPDFDocument (which logs an error on them).
private func looksLikePDF(_ path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }
    let head = handle.readData(ofLength: 1024)
    return head.range(of: Data("%PDF-".utf8)) != nil
}

// Add every frame of an image file as its own PDF page.
//
// Two sizing modes. Without a page size the page in points is pixels * 72 / dpi,
// where dpi is the override, the file's recorded DPI, or 72 - so the page is as
// big as the image claims to be. With one, every page is that fixed size and the
// image is scaled to fit inside it, centred, keeping its aspect ratio.
//
// Fit-to-page ORIENTS the page to the image: a landscape photo gets a landscape
// page rather than a portrait one with deep white bands top and bottom. A square
// image leaves the requested orientation alone.
private func addImagePages(path: String, into ctx: CGContext, dpiOverride: Double?,
                           pageSize: CGSize?) throws {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw PDFUtilError.processing("cannot open image: \(path)")
    }
    let frames = CGImageSourceGetCount(source)
    guard frames > 0 else {
        throw PDFUtilError.processing("no images found in: \(path)")
    }

    for frame in 0..<frames {
        try autoreleasepool {
            guard let image = CGImageSourceCreateImageAtIndex(source, frame, nil) else {
                throw PDFUtilError.processing("cannot read image frame \(frame + 1) of \(path)")
            }
            let imageW = Double(image.width)
            let imageH = Double(image.height)

            var box: CGRect
            var drawRect: CGRect

            if let requested = pageSize {
                var pageW = Double(requested.width)
                var pageH = Double(requested.height)
                // Match the page's orientation to the image's. Comparing the two
                // "is it wider than tall" answers turns the page only when they
                // disagree, and leaves a square image on the page as asked for.
                if (imageW > imageH) != (pageW > pageH) {
                    swap(&pageW, &pageH)
                }
                // The smaller of the two ratios is the one that fits; using it
                // for both axes is what preserves the aspect ratio.
                let scale = min(pageW / imageW, pageH / imageH)
                let drawW = imageW * scale
                let drawH = imageH * scale
                box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
                drawRect = CGRect(x: (pageW - drawW) / 2, y: (pageH - drawH) / 2,
                                  width: drawW, height: drawH)
            } else {
                let props = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any]
                let dpi: Double
                if let override = dpiOverride {
                    dpi = override
                } else if let recorded = props?[kCGImagePropertyDPIWidth] as? Double, recorded > 0 {
                    dpi = recorded
                } else {
                    dpi = 72
                }
                box = CGRect(x: 0, y: 0, width: imageW * 72.0 / dpi, height: imageH * 72.0 / dpi)
                drawRect = box
            }

            let pageInfo: [String: Any] = [
                kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size),
            ]
            ctx.beginPDFPage(pageInfo as CFDictionary)
            ctx.draw(image, in: drawRect)
            ctx.endPDFPage()
        }
    }
}
