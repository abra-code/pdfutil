// Core/Redraw.swift - the redraw path: re-record PDF pages into a fresh
// CGPDFContext. Redraw loses annotations, links, outline, and form fields (the
// content itself is re-emitted), which is why it is used only where the content
// must be transformed (reduce/linearize/pdfa/watermark). The Info metadata is
// carried across so redraw verbs do not silently drop it.

import Foundation
import CoreGraphics
import PDFKit
import Quartz

// Build the CGPDFContext page-info dictionary that preserves a page's media box,
// a distinct crop box, and its rotation.
//
// The page is drawn un-rotated and the rotation is carried on the page dictionary
// via the "Rotate" key instead. This is pdfreduce's workaround: baking the
// rotation into the CTM disables the Quartz image filter's downsampling, so we
// keep the /Rotate entry and let the viewer apply it.
private func pageInfoDictionary(for page: CGPDFPage) -> [String: Any] {
    var mediaBox = page.getBoxRect(.mediaBox)
    var cropBox = page.getBoxRect(.cropBox)
    let rotation = page.rotationAngle

    var info: [String: Any] = [
        kCGPDFContextMediaBox as String: NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size),
    ]
    if cropBox != mediaBox {
        info[kCGPDFContextCropBox as String] =
            NSData(bytes: &cropBox, length: MemoryLayout<CGRect>.size)
    }
    if rotation % 360 != 0 {
        // "Rotate" is an undocumented-but-honored CGPDFContext page key.
        info["Rotate"] = rotation
    }
    return info
}

// Redraw one source page into an open CGPDFContext, preserving its boxes and
// rotation. The faithful media/crop/rotation-preserving page copy used by
// frompages (no filter, no overlays).
func drawPDFPagePreservingBox(_ page: CGPDFPage, into ctx: CGContext) {
    ctx.beginPDFPage(pageInfoDictionary(for: page) as CFDictionary)
    ctx.drawPDFPage(page)
    ctx.endPDFPage()
}

// Translate a PDFKit document's Info attributes into CGPDFContext metadata keys,
// so a redraw carries title/author/subject/keywords/creator forward. (PDFKit and
// CoreGraphics both re-stamp Producer and the dates on write, so those are left
// to the writer.)
func metadataContextInfo(from doc: PDFDocument) -> [CFString: Any] {
    let a = readDocAttributes(doc)
    var info: [CFString: Any] = [:]
    if let v = a.title { info[kCGPDFContextTitle] = v }
    if let v = a.author { info[kCGPDFContextAuthor] = v }
    if let v = a.subject { info[kCGPDFContextSubject] = v }
    if let v = a.keywords, !v.isEmpty { info[kCGPDFContextKeywords] = v.joined(separator: ", ") }
    if let v = a.creator { info[kCGPDFContextCreator] = v }
    return info
}

// The generalized redraw engine, shared by reduce (and, later, linearize, pdfa,
// and watermark). Creates the output context with `auxiliaryInfo` (encryption,
// linearization/PDFA keys, metadata), applies an optional Quartz filter, and
// re-records every page. `underlay`/`overlay` run before/after each page's
// content; `pageRange` (0-based) limits which pages they touch (nil = all). All
// pages are always emitted regardless of `pageRange`.
func redraw(document: CGPDFDocument,
            to url: URL,
            auxiliaryInfo: [CFString: Any] = [:],
            filter: QuartzFilter? = nil,
            pageRange: [Int]? = nil,
            underlay: ((CGContext, CGPDFPage, Int) -> Void)? = nil,
            overlay: ((CGContext, CGPDFPage, Int) -> Void)? = nil) throws {
    let pageCount = document.numberOfPages
    guard pageCount > 0 else {
        throw PDFUtilError.processing("PDF has no pages")
    }

    var defaultBox = document.page(at: 1)?.getBoxRect(.mediaBox)
        ?? CGRect(x: 0, y: 0, width: 612, height: 792)
    let aux = auxiliaryInfo.isEmpty ? nil : (auxiliaryInfo as CFDictionary)
    guard let ctx = CGContext(url as CFURL, mediaBox: &defaultBox, aux) else {
        throw PDFUtilError.processing("cannot create output PDF: \(url.path)")
    }

    let marked: Set<Int>? = pageRange.map { Set($0) }
    filter?.apply(to: ctx)
    var caught: Error?
    for p in 1...pageCount {
        autoreleasepool {
            guard let page = document.page(at: p) else {
                caught = PDFUtilError.processing("cannot read page \(p)")
                return
            }
            let index = p - 1
            let applyMark = marked?.contains(index) ?? true
            ctx.beginPDFPage(pageInfoDictionary(for: page) as CFDictionary)
            if applyMark { underlay?(ctx, page, index) }
            ctx.drawPDFPage(page)
            if applyMark { overlay?(ctx, page, index) }
            ctx.endPDFPage()
        }
        if caught != nil { break }
    }
    // Remove the filter and close even on a page error, so the context is not
    // left dangling; the caller discards the temp file on the thrown error.
    filter?.remove(from: ctx)
    ctx.closePDF()
    if let caught = caught { throw caught }
}
