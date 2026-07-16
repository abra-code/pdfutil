// Core/OutlineCore.swift - read a document's outline (table of contents) into a
// nested Codable tree. Shared by the `outline` verb and, later, MCP.

import Foundation
import PDFKit

struct OutlineNode: Codable {
    let label: String
    let page: Int?          // 1-based destination page, when the node has one
    let children: [OutlineNode]
}

// Build the outline as a forest of top-level nodes, or nil when the document has
// no outline at all.
func buildOutline(doc: PDFDocument) -> [OutlineNode]? {
    guard let root = doc.outlineRoot, root.numberOfChildren > 0 else { return nil }

    func convert(_ node: PDFOutline) -> OutlineNode {
        var children: [OutlineNode] = []
        for i in 0..<node.numberOfChildren {
            if let child = node.child(at: i) { children.append(convert(child)) }
        }
        // index(for:) returns NSNotFound for a destination page that is not part
        // of this document (malformed or remote destinations); guard the +1.
        let page = node.destination?.page.flatMap { p -> Int? in
            let i = doc.index(for: p)
            return i == NSNotFound ? nil : i + 1
        }
        return OutlineNode(label: node.label ?? "", page: page, children: children)
    }

    var nodes: [OutlineNode] = []
    for i in 0..<root.numberOfChildren {
        if let child = root.child(at: i) { nodes.append(convert(child)) }
    }
    return nodes
}

func formatOutline(_ nodes: [OutlineNode], level: Int = 0) -> String {
    var s = ""
    let indent = String(repeating: "  ", count: level)
    for node in nodes {
        var line = indent + node.label
        if let page = node.page { line += "  p\(page)" }
        s += line + "\n"
        if !node.children.isEmpty { s += formatOutline(node.children, level: level + 1) }
    }
    return s
}
