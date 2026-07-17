// Core/Redraw.swift - the redraw path: re-record PDF pages into a fresh
// CGPDFContext. Redraw loses annotations, links, outline, and form fields (the
// content itself is re-emitted), which is why it is used only where the content
// must be transformed. Session 3 lifts just the per-page draw helper from
// pdfreduce; Session 4 builds the fuller redraw engine (Quartz filter,
// encryption, metadata, overlays) around it.

import Foundation
import CoreGraphics

// Redraw one source page into an open CGPDFContext, preserving its media box, a
// distinct crop box, and its rotation.
//
// The page is drawn un-rotated and the rotation is carried on the page dictionary
// via the "Rotate" key instead. This is pdfreduce's workaround: baking the
// rotation into the CTM disables the Quartz image filter's downsampling, so we
// keep the /Rotate entry and let the viewer apply it. The same helper is reused
// where there is no filter (frompages), where it is simply the faithful
// media/crop/rotation-preserving page copy.
func drawPDFPagePreservingBox(_ page: CGPDFPage, into ctx: CGContext) {
    var mediaBox = page.getBoxRect(.mediaBox)
    var cropBox = page.getBoxRect(.cropBox)
    let rotation = page.rotationAngle

    var pageInfo: [String: Any] = [
        kCGPDFContextMediaBox as String: NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size),
    ]
    if cropBox != mediaBox {
        pageInfo[kCGPDFContextCropBox as String] =
            NSData(bytes: &cropBox, length: MemoryLayout<CGRect>.size)
    }
    if rotation % 360 != 0 {
        // "Rotate" is an undocumented-but-honored CGPDFContext page key.
        pageInfo["Rotate"] = rotation
    }

    ctx.beginPDFPage(pageInfo as CFDictionary)
    ctx.drawPDFPage(page)
    ctx.endPDFPage()
}
