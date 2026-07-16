// Core/GeometryCore.swift - page rotation and box cropping (structure-preserving,
// via PDFPage.rotation and setBounds). Shared by the rotate and crop verbs.

import Foundation
import PDFKit
import CoreGraphics

// Rotate the given pages by `degrees`, normalizing the result to 0/90/180/270.
func rotatePages(doc: PDFDocument, pages: [Int], degrees: Int) {
    for idx in pages {
        autoreleasepool {
            guard let page = doc.page(at: idx) else { return }
            page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
        }
    }
}

enum CropSpec {
    case rect([Double])       // x, y, width, height (page space, origin bottom-left)
    case margins([Double])    // left, bottom, right, top insets of the current box
}

// Set the chosen box on each page from an absolute rect or by insetting the
// current box. Rejects an empty or inverted result as a usage error.
func cropPages(doc: PDFDocument, pages: [Int], box: PDFDisplayBox, spec: CropSpec) throws {
    for idx in pages {
        try autoreleasepool {
            guard let page = doc.page(at: idx) else { return }
            let rect: CGRect
            switch spec {
            case .rect(let r):
                rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
            case .margins(let m):
                let cur = page.bounds(for: box)
                rect = CGRect(x: cur.minX + m[0], y: cur.minY + m[1],
                              width: cur.width - m[0] - m[2], height: cur.height - m[1] - m[3])
            }
            // Guard the raw size (CGRect.width/.height report the standardized,
            // always-nonnegative extent, which would hide an inverted rect).
            guard rect.size.width > 0, rect.size.height > 0 else {
                throw PDFUtilError.usage("crop leaves no page area on page \(idx + 1)")
            }
            page.setBounds(rect, for: box)
        }
    }
}

func parseBox(_ name: String) throws -> PDFDisplayBox {
    switch name.lowercased() {
    case "media": return .mediaBox
    case "crop": return .cropBox
    case "art": return .artBox
    case "bleed": return .bleedBox
    case "trim": return .trimBox
    default: throw PDFUtilError.usage("--box must be one of media, crop, art, bleed, trim")
    }
}

// Parse exactly four comma-separated numbers for --rect / --margins.
func parseFour(_ spec: String, option: String) throws -> [Double] {
    let parts = spec.split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 4 else {
        throw PDFUtilError.usage("\(option) expects four comma-separated numbers")
    }
    var values: [Double] = []
    for part in parts {
        guard let d = Double(part) else {
            throw PDFUtilError.usage("\(option) has a non-number '\(part)'")
        }
        values.append(d)
    }
    return values
}
