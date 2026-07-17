// Core/RenderCore.swift - rasterize PDF pages to images via a CGBitmapContext and
// CGImageDestination (the pdftoppm role). Renders one page to a CGImage and,
// separately, writes a CGImage to a file, so the MCP pdf_render tool can reuse
// the render half without touching the filesystem.

import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageFormat: String {
    case png, jpeg, tiff, heic

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .heic: return .heic
        }
    }
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        case .heic: return "heic"
        }
    }
    var supportsTransparency: Bool { self != .jpeg }
    var isLossy: Bool { self == .jpeg || self == .heic }
}

func parseImageFormat(_ s: String) throws -> ImageFormat {
    guard let format = ImageFormat(rawValue: s.lowercased()) else {
        throw PDFUtilError.usage("--format must be png, jpeg, tiff, or heic")
    }
    return format
}

// Drop a trailing image extension so an -o value can serve as a multi-page prefix.
func stripImageExtension(_ path: String) -> String {
    let lower = path.lowercased()
    for ext in [".png", ".jpg", ".jpeg", ".tiff", ".tif", ".heic"] where lower.hasSuffix(ext) {
        return String(path.dropLast(ext.count))
    }
    return path
}

// Render one page (its crop box) at the given DPI into an sRGB bitmap. When not
// transparent, the bitmap is filled white first. Rotated pages produce a
// correctly oriented (and correctly proportioned) image.
func renderPageToImage(_ page: PDFPage, dpi: Double, transparent: Bool) throws -> CGImage {
    let bounds = page.bounds(for: .cropBox)
    var widthPts = Double(bounds.width)
    var heightPts = Double(bounds.height)
    if page.rotation % 180 == 90 { swap(&widthPts, &heightPts) }

    let scale = dpi / 72.0
    // Compute pixels as points*dpi/72 (exact intermediate) rather than points*scale,
    // so e.g. 792 pt at 150 dpi is 1650, not 1651 from a float-rounded scale.
    let widthPx = (widthPts * dpi / 72.0).rounded(.up)
    let heightPx = (heightPts * dpi / 72.0).rounded(.up)
    // Cap the dimensions so an extreme DPI fails cleanly instead of trapping in
    // the Int() cast or driving a multi-terabyte bitmap allocation.
    let maxDimension = 30_000.0
    guard widthPx > 0, heightPx > 0 else {
        throw PDFUtilError.processing("page has zero size")
    }
    guard widthPx <= maxDimension, heightPx <= maxDimension else {
        // Format the doubles directly; Int() on a huge value would itself trap.
        throw PDFUtilError.processing(String(format:
            "requested resolution is too large (%.0fx%.0f px, max %.0f per side); lower --dpi/--scale",
            widthPx, heightPx, maxDimension))
    }
    let pixelW = Int(widthPx)
    let pixelH = Int(heightPx)

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: pixelW, height: pixelH,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw PDFUtilError.processing("cannot create a \(pixelW)x\(pixelH) bitmap context")
    }
    if !transparent {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
    }
    ctx.scaleBy(x: scale, y: scale)
    page.draw(with: .cropBox, to: ctx)

    guard let image = ctx.makeImage() else {
        throw PDFUtilError.processing("cannot rasterize page")
    }
    return image
}

// Write a CGImage to a file, recording its DPI and (for lossy formats) quality.
func writeCGImage(_ image: CGImage, to url: URL, format: ImageFormat,
                  quality: Double, dpi: Double) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, format.utType.identifier as CFString, 1, nil) else {
        throw PDFUtilError.processing("cannot create image output: \(url.path)")
    }
    var props: [CFString: Any] = [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi,
    ]
    if format.isLossy {
        props[kCGImageDestinationLossyCompressionQuality] = quality
    }
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw PDFUtilError.processing("cannot write image: \(url.path)")
    }
}
