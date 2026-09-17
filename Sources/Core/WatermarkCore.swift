// Core/WatermarkCore.swift - stamp a text or image watermark onto pages.
//
// Two paths, chosen by mode:
//  - Burn-in (default): the redraw engine with an overlay (or underlay) closure
//    that draws the mark with position, rotation, and opacity. Because it redraws
//    the whole document, annotations/links/outline/form fields are not carried
//    over (only the mark's rotation is possible this way; a freeText annotation
//    cannot rotate). Used for both --text and --image.
//  - Annotation (--text only): add an axis-aligned freeText annotation and save.
//    Structure-preserving and interactive; rotation does not apply.

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import AppKit

enum WatermarkPosition: String {
    case center
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
}

struct WatermarkSpec {
    var text: String?
    var imagePath: String?
    var position: WatermarkPosition = .center
    var rotateMark: Double = 45      // degrees, burn-in only
    var opacity: Double = 0.25       // 0...1
    var pointSize: Double?           // nil = 1/10 of the page diagonal (text)
    var under = false                // draw beneath the page content
    var annotation = false           // structure-preserving freeText path
}

private func pageDiagonal(_ box: CGRect) -> Double {
    Double((box.width * box.width + box.height * box.height).squareRoot())
}

// The point on which the mark is centered, kept a margin inside the box for the
// corner positions so the (centered) mark stays on the page.
private func anchorPoint(box: CGRect, width: CGFloat, height: CGFloat,
                         position: WatermarkPosition) -> CGPoint {
    let margin = max(width, height) / 2 + 18
    switch position {
    case .center: return CGPoint(x: box.midX, y: box.midY)
    case .topLeft: return CGPoint(x: box.minX + margin, y: box.maxY - margin)
    case .topRight: return CGPoint(x: box.maxX - margin, y: box.maxY - margin)
    case .bottomLeft: return CGPoint(x: box.minX + margin, y: box.minY + margin)
    case .bottomRight: return CGPoint(x: box.maxX - margin, y: box.minY + margin)
    }
}

private func drawTextMark(_ ctx: CGContext, box: CGRect, text: String, spec: WatermarkSpec) {
    let size = spec.pointSize ?? pageDiagonal(box) / 10
    let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.5, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let anchor = anchorPoint(box: box, width: width, height: ascent + descent, position: spec.position)

    ctx.saveGState()
    ctx.setAlpha(CGFloat(spec.opacity))
    ctx.translateBy(x: anchor.x, y: anchor.y)
    ctx.rotate(by: CGFloat(spec.rotateMark * .pi / 180))
    ctx.textPosition = CGPoint(x: -width / 2, y: -(ascent - descent) / 2)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

private func drawImageMark(_ ctx: CGContext, box: CGRect, image: CGImage, spec: WatermarkSpec) {
    // Fit the image to half the box's shorter side, preserving aspect ratio.
    let target = min(box.width, box.height) * 0.5
    let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
    var w = target, h = target * aspect
    if h > target { h = target; w = target / max(aspect, 0.0001) }
    let anchor = anchorPoint(box: box, width: w, height: h, position: spec.position)

    ctx.saveGState()
    ctx.setAlpha(CGFloat(spec.opacity))
    ctx.translateBy(x: anchor.x, y: anchor.y)
    ctx.rotate(by: CGFloat(spec.rotateMark * .pi / 180))
    ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    ctx.restoreGState()
}

private func loadWatermarkImage(_ path: String) throws -> CGImage {
    guard FileManager.default.fileExists(atPath: path) else {
        throw PDFUtilError.processing("watermark image not found: \(path)")
    }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw PDFUtilError.processing("cannot read watermark image: \(path)")
    }
    return image
}

// Burn-in path: redraw the document, drawing the mark over (or under) the marked
// pages. `pages` (0-based; nil = all) selects which pages get the mark; every
// page is redrawn regardless.
func watermarkBurnIn(path: String, output: String?, force: Bool, password: String?,
                     pages: [Int]?, spec: WatermarkSpec) throws {
    let cgDoc = try openCGPDF(path: path, password: password)
    let image = spec.imagePath != nil ? try loadWatermarkImage(spec.imagePath!) : nil

    var aux: [CFString: Any] = [:]
    if let doc = try? openPDF(path: path, password: password) {
        aux = metadataContextInfo(from: doc)
    }

    let draw: (CGContext, CGPDFPage, Int) -> Void = { ctx, page, _ in
        let box = page.getBoxRect(.cropBox)
        if let text = spec.text {
            drawTextMark(ctx, box: box, text: text, spec: spec)
        } else if let image = image {
            drawImageMark(ctx, box: box, image: image, spec: spec)
        }
    }

    try writeAtomically(to: output, force: force, inPlaceOf: path) { tmpURL in
        try redraw(document: cgDoc, to: tmpURL, auxiliaryInfo: aux, filter: nil,
                   pageRange: pages,
                   underlay: spec.under ? draw : nil,
                   overlay: spec.under ? nil : draw)
    }
}

// Annotation path: add a freeText watermark annotation to the selected pages and
// save (structure-preserving). Text only; axis-aligned (rotation ignored).
func watermarkAnnotation(doc: PDFDocument, output: String?, force: Bool,
                         pages: [Int]?, spec: WatermarkSpec, inPlaceOf path: String,
                         password: String?) throws {
    guard let text = spec.text else {
        throw PDFUtilError.usage("--annotation supports only --text (not --image)")
    }
    try requirePermission(doc.allowsCommenting, "adding annotations", in: doc)
    let indices = pages ?? Array(0..<doc.pageCount)
    for idx in indices {
        autoreleasepool {
            guard let page = doc.page(at: idx) else { return }
            let box = page.bounds(for: .cropBox)
            let size = spec.pointSize ?? pageDiagonal(box) / 10
            let font = NSFont(name: "Helvetica", size: CGFloat(size))
                ?? NSFont.systemFont(ofSize: CGFloat(size))
            let textSize = (text as NSString).size(withAttributes: [.font: font])
            let w = textSize.width + 8, h = textSize.height + 8
            let anchor = anchorPoint(box: box, width: w, height: h, position: spec.position)
            let bounds = CGRect(x: anchor.x - w / 2, y: anchor.y - h / 2, width: w, height: h)

            let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
            annotation.contents = text
            annotation.font = font
            annotation.fontColor = NSColor(white: 0.5, alpha: CGFloat(spec.opacity))
            annotation.color = .clear
            page.addAnnotation(annotation)
        }
    }
    try savePDF(doc, to: output, writeOptions: [:], force: force, inPlaceOf: path, password: password)
}
