// Core/InfoCore.swift - document introspection for the `info` verb. Reads the
// PDF version from CoreGraphics and everything else from PDFKit, and provides
// both the Codable result (for --json) and the human formatter.

import Foundation
import PDFKit
import CoreGraphics

// A rectangle as plain numbers, so boxes serialize as {x, y, width, height}.
struct Box: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ r: CGRect) {
        x = Double(r.origin.x)
        y = Double(r.origin.y)
        width = Double(r.size.width)
        height = Double(r.size.height)
    }
}

// The Info-dictionary attributes that PDFKit exposes; only present ones encode.
struct DocAttributes: Codable {
    var title: String?
    var author: String?
    var subject: String?
    var keywords: [String]?
    var creator: String?
    var producer: String?
    var creationDate: Date?
    var modificationDate: Date?
}

struct PageInfo: Codable {
    let index: Int          // 1-based
    let mediaBox: Box
    let cropBox: Box?       // present only when it differs from the media box
    let rotation: Int
    let hasText: Bool
}

struct DocInfo: Codable {
    let file: String
    let pdfVersion: String
    let pageCount: Int
    let encrypted: Bool
    let locked: Bool
    let permissions: [String]
    let attributes: DocAttributes
    let outlineItems: Int
    let pages: [PageInfo]
}

// The eight access-permission flags and the short names shared with `encrypt`.
let kPermissionFlags: [(PDFAccessPermissions, String)] = [
    (.allowsLowQualityPrinting, "printing"),
    (.allowsHighQualityPrinting, "high-quality-printing"),
    (.allowsDocumentChanges, "changes"),
    (.allowsDocumentAssembly, "assembly"),
    (.allowsContentCopying, "copying"),
    (.allowsContentAccessibility, "accessibility"),
    (.allowsCommenting, "commenting"),
    (.allowsFormFieldEntry, "forms"),
]

// PDFAccessPermissions is an NS_ENUM whose cases are single bits; the document's
// accessPermissions value ORs them together, so we test membership on the bits.
func permissionNames(_ perms: PDFAccessPermissions) -> [String] {
    let bits = perms.rawValue
    return kPermissionFlags.filter { (bits & $0.0.rawValue) != 0 }.map { $0.1 }
}

// Count every node under the outline root (the root itself is not a node).
func countOutline(_ root: PDFOutline?) -> Int {
    guard let root = root else { return 0 }
    var total = 0
    for i in 0..<root.numberOfChildren {
        if let child = root.child(at: i) { total += 1 + countOutline(child) }
    }
    return total
}

func gatherInfo(path: String, doc: PDFDocument, cgDoc: CGPDFDocument) -> DocInfo {
    var major: Int32 = 0
    var minor: Int32 = 0
    cgDoc.getVersion(majorVersion: &major, minorVersion: &minor)

    let attrs = doc.documentAttributes ?? [:]
    func string(_ key: PDFDocumentAttribute) -> String? { attrs[key] as? String }
    func date(_ key: PDFDocumentAttribute) -> Date? { attrs[key] as? Date }

    var attributes = DocAttributes()
    attributes.title = string(.titleAttribute)
    attributes.author = string(.authorAttribute)
    attributes.subject = string(.subjectAttribute)
    attributes.creator = string(.creatorAttribute)
    attributes.producer = string(.producerAttribute)
    attributes.creationDate = date(.creationDateAttribute)
    attributes.modificationDate = date(.modificationDateAttribute)
    if let keywords = attrs[PDFDocumentAttribute.keywordsAttribute] as? [String] {
        attributes.keywords = keywords
    } else if let keyword = attrs[PDFDocumentAttribute.keywordsAttribute] as? String {
        attributes.keywords = [keyword]
    }

    var pages: [PageInfo] = []
    pages.reserveCapacity(doc.pageCount)
    for i in 0..<doc.pageCount {
        autoreleasepool {
            guard let page = doc.page(at: i) else { return }
            let media = page.bounds(for: .mediaBox)
            let crop = page.bounds(for: .cropBox)
            let hasText = !(page.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            pages.append(PageInfo(
                index: i + 1,
                mediaBox: Box(media),
                cropBox: crop.equalTo(media) ? nil : Box(crop),
                rotation: page.rotation,
                hasText: hasText))
        }
    }

    return DocInfo(
        file: path,
        pdfVersion: "\(major).\(minor)",
        pageCount: doc.pageCount,
        encrypted: doc.isEncrypted,
        locked: doc.isLocked,
        permissions: permissionNames(doc.accessPermissions),
        attributes: attributes,
        outlineItems: countOutline(doc.outlineRoot),
        pages: pages)
}

// Format a dimension without a trailing ".0" for the common whole-point case.
private func dim(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d)
}

private func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

func formatInfo(_ info: DocInfo) -> String {
    var s = ""
    s += "file: \(info.file)\n"
    s += "version: \(info.pdfVersion)\n"
    s += "pages: \(info.pageCount)\n"
    s += "encrypted: \(info.encrypted)\n"
    s += "locked: \(info.locked)\n"
    if !info.permissions.isEmpty {
        s += "permissions: \(info.permissions.joined(separator: ", "))\n"
    }

    let a = info.attributes
    if let v = a.title { s += "title: \(v)\n" }
    if let v = a.author { s += "author: \(v)\n" }
    if let v = a.subject { s += "subject: \(v)\n" }
    if let v = a.keywords { s += "keywords: \(v.joined(separator: ", "))\n" }
    if let v = a.creator { s += "creator: \(v)\n" }
    if let v = a.producer { s += "producer: \(v)\n" }
    if let v = a.creationDate { s += "created: \(iso8601(v))\n" }
    if let v = a.modificationDate { s += "modified: \(iso8601(v))\n" }

    s += "outline items: \(info.outlineItems)\n\n"

    for p in info.pages {
        var line = "page \(p.index): \(dim(p.mediaBox.width))x\(dim(p.mediaBox.height)) pt"
        if let c = p.cropBox { line += ", crop \(dim(c.width))x\(dim(c.height)) pt" }
        if p.rotation != 0 { line += ", rotation \(p.rotation)" }
        line += p.hasText ? ", text" : ", no text"
        s += line + "\n"
    }
    return s
}
