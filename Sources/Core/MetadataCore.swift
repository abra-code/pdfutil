// Core/MetadataCore.swift - read and edit the Info-dictionary attributes
// (structure-preserving). Shared by the metadata verb; the reader is also used
// by the info verb.

import Foundation
import PDFKit

// Read the present Info-dictionary attributes into DocAttributes (defined in
// InfoCore). Only keys that exist are populated.
func readDocAttributes(_ doc: PDFDocument) -> DocAttributes {
    let attrs = doc.documentAttributes ?? [:]
    func string(_ key: PDFDocumentAttribute) -> String? { attrs[key] as? String }
    func date(_ key: PDFDocumentAttribute) -> Date? { attrs[key] as? Date }

    var result = DocAttributes()
    result.title = string(.titleAttribute)
    result.author = string(.authorAttribute)
    result.subject = string(.subjectAttribute)
    result.creator = string(.creatorAttribute)
    result.producer = string(.producerAttribute)
    result.creationDate = date(.creationDateAttribute)
    result.modificationDate = date(.modificationDateAttribute)
    if let keywords = attrs[PDFDocumentAttribute.keywordsAttribute] as? [String] {
        result.keywords = keywords
    } else if let keyword = attrs[PDFDocumentAttribute.keywordsAttribute] as? String {
        result.keywords = [keyword]
    }
    return result
}

func formatAttributes(_ a: DocAttributes) -> String {
    var s = ""
    if let v = a.title { s += "title: \(v)\n" }
    if let v = a.author { s += "author: \(v)\n" }
    if let v = a.subject { s += "subject: \(v)\n" }
    if let v = a.keywords { s += "keywords: \(v.joined(separator: ", "))\n" }
    if let v = a.creator { s += "creator: \(v)\n" }
    if let v = a.producer { s += "producer: \(v)\n" }
    if let v = a.creationDate { s += "created: \(ISO8601DateFormatter().string(from: v))\n" }
    if let v = a.modificationDate { s += "modified: \(ISO8601DateFormatter().string(from: v))\n" }
    return s.isEmpty ? "(no metadata)\n" : s
}

struct MetadataEdit {
    var sets: [(key: String, value: String)] = []
    var deletes: [String] = []
    var strip = false

    var mutates: Bool { !sets.isEmpty || !deletes.isEmpty || strip }
}

func metadataAttribute(for rawKey: String) throws -> PDFDocumentAttribute {
    switch rawKey.lowercased() {
    case "title": return .titleAttribute
    case "author": return .authorAttribute
    case "subject": return .subjectAttribute
    case "keywords": return .keywordsAttribute
    case "creator": return .creatorAttribute
    case "producer": return .producerAttribute
    case "creation-date": return .creationDateAttribute
    case "modification-date": return .modificationDateAttribute
    default: throw PDFUtilError.usage("unknown metadata key '\(rawKey)' (title, author, subject, keywords, creator, producer, creation-date, modification-date)")
    }
}

// Convert a --set VALUE to the type PDFKit expects for that key.
private func metadataValue(for rawKey: String, _ rawValue: String) throws -> Any {
    switch rawKey.lowercased() {
    case "keywords":
        return rawValue.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    case "creation-date", "modification-date":
        guard let date = ISO8601DateFormatter().date(from: rawValue) else {
            throw PDFUtilError.usage("date for '\(rawKey)' must be ISO 8601 (got '\(rawValue)')")
        }
        return date
    default:
        return rawValue
    }
}

// Apply the edit to the document's attributes in memory (caller then saves).
func applyMetadata(doc: PDFDocument, edit: MetadataEdit) throws {
    try requirePermission(doc.allowsDocumentChanges, "changing the document information", in: doc)
    var attrs: [AnyHashable: Any] = edit.strip ? [:] : (doc.documentAttributes ?? [:])
    for (key, value) in edit.sets {
        attrs[try metadataAttribute(for: key)] = try metadataValue(for: key, value)
    }
    for key in edit.deletes {
        attrs[try metadataAttribute(for: key)] = nil
    }
    doc.documentAttributes = attrs
}
