// Core/FromPagesCore.swift - assemble images and/or PDFs into one PDF (the
// img2pdf role, plus mixed inputs). Images become one page each (sized from
// their pixel dimensions and DPI); PDF inputs are redrawn page by page.

import Foundation
import CoreGraphics
import ImageIO

// Combine the inputs, in order, into a single PDF written to `output`. Each input
// is classified by whether CoreGraphics opens it as a PDF; otherwise it is read
// as an image (multi-frame images contribute one page per frame).
func combineToPDF(inputs: [String], output: String, dpiOverride: Double?, force: Bool) throws {
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
                try addImagePages(path: path, into: ctx, dpiOverride: dpiOverride)
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

// Add every frame of an image file as its own PDF page. The page size in points
// is pixels * 72 / dpi, where dpi is the override, the file's recorded DPI, or 72.
private func addImagePages(path: String, into ctx: CGContext, dpiOverride: Double?) throws {
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
            let props = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any]
            let dpi: Double
            if let override = dpiOverride {
                dpi = override
            } else if let recorded = props?[kCGImagePropertyDPIWidth] as? Double, recorded > 0 {
                dpi = recorded
            } else {
                dpi = 72
            }

            let widthPts = Double(image.width) * 72.0 / dpi
            let heightPts = Double(image.height) * 72.0 / dpi
            var box = CGRect(x: 0, y: 0, width: widthPts, height: heightPts)
            let pageInfo: [String: Any] = [
                kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size),
            ]
            ctx.beginPDFPage(pageInfo as CFDictionary)
            ctx.draw(image, in: box)
            ctx.endPDFPage()
        }
    }
}
