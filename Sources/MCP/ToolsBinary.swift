// MCP/ToolsBinary.swift - the MCP tools that return binary or heavier content:
// pdf_render (a PNG image content item), pdf_ocr (Vision text), and
// pdf_forms_list (JSON). Registered in Tools.swift's dispatch and schemas.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

private let kMaxOcrCharacters = 50_000
private let kMaxRenderDPI = 300.0

// Encode a CGImage to PNG bytes in memory (for base64 image content).
private func encodePNGData(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
        throw PDFUtilError.processing("cannot create a PNG encoder")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw PDFUtilError.processing("cannot encode PNG")
    }
    return data as Data
}

// pdf_render: rasterize one page to PNG and return it as a base64 image item.
func toolPdfRender(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    guard let page1 = optionalInt(arguments, "page") else {
        throw PDFUtilError.usage("missing or invalid 'page' (a single 1-based page number)")
    }
    let doc = try openPDF(path: path, password: optionalString(arguments, "password"))
    guard page1 >= 1, page1 <= doc.pageCount, let page = doc.page(at: page1 - 1) else {
        throw PDFUtilError.usage("page \(page1) out of range (1-\(doc.pageCount))")
    }
    // dpi default 150, capped at 300 for an MCP payload.
    let requested = Double(optionalInt(arguments, "dpi") ?? 150)
    let dpi = min(kMaxRenderDPI, max(1, requested))

    let image = try renderPageToImage(page, dpi: dpi, transparent: false)
    let png = try encodePNGData(image)
    return toolImage(base64: png.base64EncodedString(), mimeType: "image/png")
}

// pdf_ocr: recognize text with Vision (rasterizes each page). Same 50k cap as
// pdf_text.
func toolPdfOcr(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let doc = try openPDF(path: path, password: optionalString(arguments, "password"))
    let pages = try resolvePages(optionalString(arguments, "pages"), pageCount: doc.pageCount)
        ?? Array(0..<doc.pageCount)
    let languages = (arguments["languages"] as? [String]) ?? []

    let text = try ocrText(doc: doc, pages: pages, dpi: 300, languages: languages, fast: false)
    if text.count > kMaxOcrCharacters {
        return toolError("recognized text is \(text.count) characters (cap \(kMaxOcrCharacters)); narrow the request with the 'pages' parameter")
    }
    return toolText(text)
}

// pdf_forms_list: list the AcroForm fields as JSON.
func toolPdfFormsList(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let doc = try openPDF(path: path, password: optionalString(arguments, "password"))
    return toolText(try encodeJSONString(gatherFormFields(doc)))
}
