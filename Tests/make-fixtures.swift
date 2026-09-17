// make-fixtures.swift - generate the deterministic PDF fixtures the test suite
// exercises. Run with the Swift interpreter:
//
//     swift Tests/make-fixtures.swift Tests/fixtures
//
// Fixtures are gitignored; only this generator is committed. No dates or other
// nondeterministic content is written into the PDFs.

import Foundation
import PDFKit
import CoreGraphics
import CoreText
import CryptoKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make-fixtures.swift <outdir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func out(_ name: String) -> URL { outDir.appendingPathComponent(name) }

let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

// Draw a single CoreText line at a baseline point.
func drawLine(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attributed = NSAttributedString(string: text, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

// text.pdf - 5 pages, one marker + one sentence each; "needle" only on page 3.
do {
    var box = letter
    guard let ctx = CGContext(out("text.pdf") as CFURL, mediaBox: &box, nil) else {
        fatalError("cannot create text.pdf")
    }
    let sentences = [
        "The quick brown fox jumps over the lazy dog.",
        "Sphinx of black quartz, judge my vow.",
        "This page hides a needle in the haystack.",
        "Pack my box with five dozen liquor jugs.",
        "How vexingly quick daft zebras jump.",
    ]
    for p in 0..<5 {
        ctx.beginPDFPage(nil)
        drawLine(ctx, "PAGE-\(p + 1)-MARKER", x: 72, y: 700, size: 24)
        drawLine(ctx, sentences[p], x: 72, y: 650, size: 18)
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

// rotated.pdf - text.pdf with every page rotated 90 degrees.
do {
    guard let doc = PDFDocument(url: out("text.pdf")) else { fatalError("reopen text.pdf") }
    for i in 0..<doc.pageCount { doc.page(at: i)?.rotation = 90 }
    doc.write(to: out("rotated.pdf"))
}

// image.pdf - 2 image-only pages (a simulated 200 dpi scan, no text layer).
do {
    func raster(_ text: String) -> CGImage {
        let width = 1700, height = 2200
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("cannot create bitmap context")
        }
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawLine(bitmap, text, x: 120, y: 2000, size: 64)
        guard let image = bitmap.makeImage() else { fatalError("makeImage failed") }
        return image
    }
    var box = letter
    guard let ctx = CGContext(out("image.pdf") as CFURL, mediaBox: &box, nil) else {
        fatalError("cannot create image.pdf")
    }
    for text in ["OCRTEST HELLO 12345", "SECOND PAGE SCAN"] {
        ctx.beginPDFPage(nil)
        ctx.draw(raster(text), in: letter)
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

// outline.pdf - text.pdf with a three-chapter outline.
do {
    guard let doc = PDFDocument(url: out("text.pdf")) else { fatalError("reopen text.pdf") }
    let root = PDFOutline()
    doc.outlineRoot = root
    func chapter(_ label: String, page idx: Int) {
        let node = PDFOutline()
        node.label = label
        if let page = doc.page(at: idx) {
            node.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
        }
        root.insertChild(node, at: root.numberOfChildren)
    }
    chapter("Chapter 1", page: 0)
    chapter("Chapter 2", page: 2)
    chapter("Chapter 3", page: 4)
    doc.write(to: out("outline.pdf"))
}

// form.pdf - one page with a text field ("name") and a checkbox ("agree").
do {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        fatalError("cannot create data consumer")
    }
    var box = letter
    guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        fatalError("cannot create form base context")
    }
    ctx.beginPDFPage(nil)
    drawLine(ctx, "Form fixture", x: 72, y: 720, size: 18)
    ctx.endPDFPage()
    ctx.closePDF()

    guard let doc = PDFDocument(data: data as Data), let page = doc.page(at: 0) else {
        fatalError("cannot build form base document")
    }
    let name = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 200, height: 24),
                             forType: .widget, withProperties: nil)
    name.widgetFieldType = .text
    name.fieldName = "name"
    page.addAnnotation(name)

    let agree = PDFAnnotation(bounds: CGRect(x: 72, y: 560, width: 24, height: 24),
                              forType: .widget, withProperties: nil)
    agree.widgetFieldType = .button
    agree.widgetControlType = .checkBoxControl
    agree.fieldName = "agree"
    page.addAnnotation(agree)

    doc.write(to: out("form.pdf"))
}

// form-filled.pdf - a one-page form with the "name" text field pre-filled
// ("Alice"), so the flatten test can confirm the value burns into the page.
do {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        fatalError("cannot create data consumer")
    }
    var box = letter
    guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        fatalError("cannot create form base context")
    }
    ctx.beginPDFPage(nil)
    drawLine(ctx, "Filled form fixture", x: 72, y: 720, size: 18)
    ctx.endPDFPage()
    ctx.closePDF()

    guard let doc = PDFDocument(data: data as Data), let page = doc.page(at: 0) else {
        fatalError("cannot build filled-form base document")
    }
    let name = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 200, height: 24),
                             forType: .widget, withProperties: nil)
    name.widgetFieldType = .text
    name.fieldName = "name"
    name.widgetStringValue = "Alice"
    page.addAnnotation(name)

    doc.write(to: out("form-filled.pdf"))
}

// locked.pdf - text.pdf saved with a user and owner password.
do {
    guard let doc = PDFDocument(url: out("text.pdf")) else { fatalError("reopen text.pdf") }
    doc.write(to: out("locked.pdf"),
              withOptions: [.userPasswordOption: "test", .ownerPasswordOption: "owner"])
}

// restricted.pdf and restricted-form.pdf - text.pdf and form.pdf protected by an
// owner password ("owner") alone. They open without a password, but only
// printing and copying are allowed: no page assembly, changes, commenting or
// form filling.
do {
    let allowed = [PDFAccessPermissions.allowsLowQualityPrinting, .allowsHighQualityPrinting,
                   .allowsContentCopying, .allowsContentAccessibility]
        .reduce(UInt(0)) { $0 | $1.rawValue }
    for (source, name) in [("text.pdf", "restricted.pdf"), ("form.pdf", "restricted-form.pdf")] {
        guard let doc = PDFDocument(url: out(source)) else { fatalError("reopen \(source)") }
        doc.write(to: out(name),
                  withOptions: [.userPasswordOption: "", .ownerPasswordOption: "owner",
                                .accessPermissionsOption: NSNumber(value: allowed)])
    }
}

// odd-permissions.pdf - 3 pages ("PAGE-n-MARKER"), encrypted with the standard
// security handler (revision 3, 128-bit RC4) and an empty user password, with
// every permission allowed but the permission value /P written as the positive
// number 3900 instead of the standard negative form. Readers accept it, and so
// does PDFKit, but a PDFKit re-save rewrites /P without recomputing the password
// check and the copy no longer opens. A real-world PDF of this kind is what
// found the bug. Neither PDFKit nor qpdf can write such a file, so it is built
// by hand here, following the PDF 1.7 standard security handler (algorithms 2,
// 3 and 5).
do {
    let padding: [UInt8] = [0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56,
                            0xFF, 0xFA, 0x01, 0x08, 0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
                            0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A]
    let permissions: Int32 = 3900
    let fileID = Array("pdfutil-odd-perm".utf8)   // 16 bytes

    func md5(_ bytes: [UInt8]) -> [UInt8] { Array(Insecure.MD5.hash(data: Data(bytes))) }
    func rc4(_ key: [UInt8], _ data: [UInt8]) -> [UInt8] {
        var s = (0...255).map { UInt8($0) }
        var j = 0
        for i in 0..<256 {
            j = (j + Int(s[i]) + Int(key[i % key.count])) & 0xFF
            s.swapAt(i, j)
        }
        var i = 0
        j = 0
        return data.map { byte in
            i = (i + 1) & 0xFF
            j = (j + Int(s[i])) & 0xFF
            s.swapAt(i, j)
            return byte ^ s[(Int(s[i]) + Int(s[j])) & 0xFF]
        }
    }
    func padded(_ password: String) -> [UInt8] { Array((Array(password.utf8) + padding).prefix(32)) }
    func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined() }

    // Algorithm 3: /O, from the owner password "owner" and the empty user password.
    var ownerHash = md5(padded("owner"))
    for _ in 0..<50 { ownerHash = md5(ownerHash) }
    let ownerKey = Array(ownerHash.prefix(16))
    var o = rc4(ownerKey, padded(""))
    for n in 1...19 { o = rc4(ownerKey.map { $0 ^ UInt8(n) }, o) }

    // Algorithm 2: the file key. /P enters as its four low-order bytes.
    let bits = UInt32(bitPattern: permissions)
    let pBytes = [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF),
                  UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF)]
    var keyHash = md5(padded("") + o + pBytes + fileID)
    for _ in 0..<50 { keyHash = md5(Array(keyHash.prefix(16))) }
    let fileKey = Array(keyHash.prefix(16))

    // Algorithm 5: /U.
    var u = rc4(fileKey, md5(padding + fileID))
    for n in 1...19 { u = rc4(fileKey.map { $0 ^ UInt8(n) }, u) }
    u += [UInt8](repeating: 0, count: 16)

    // Each stream is encrypted with a key derived from its object number
    // (generation 0).
    func objectKey(_ number: Int) -> [UInt8] {
        Array(md5(fileKey + [UInt8(number & 0xFF), UInt8((number >> 8) & 0xFF),
                             UInt8((number >> 16) & 0xFF), 0, 0]).prefix(16))
    }

    var body = Array("%PDF-1.4\n".utf8)
    var offsets: [Int] = []
    func object(_ number: Int, _ text: String, stream: [UInt8]? = nil) {
        offsets.append(body.count)
        body += Array("\(number) 0 obj\n\(text)\n".utf8)
        if let stream = stream {
            body += Array("stream\n".utf8) + stream + Array("\nendstream\n".utf8)
        }
        body += Array("endobj\n".utf8)
    }

    object(1, "<< /Type /Catalog /Pages 2 0 R >>")
    object(2, "<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 >>")
    for page in 0..<3 {
        let pageObject = 3 + page * 2
        let contentObject = pageObject + 1
        object(pageObject, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 9 0 R >> >> /Contents \(contentObject) 0 R >>")
        let content = Array("BT /F1 24 Tf 72 700 Td (PAGE-\(page + 1)-MARKER) Tj ET".utf8)
        let encrypted = rc4(objectKey(contentObject), content)
        object(contentObject, "<< /Length \(encrypted.count) >>", stream: encrypted)
    }
    object(9, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    object(10, "<< /Filter /Standard /V 2 /R 3 /Length 128 /P \(permissions) /O <\(hex(o))> /U <\(hex(u))> >>")

    let xrefOffset = body.count
    var xref = "xref\n0 11\n0000000000 65535 f \n"
    for offset in offsets { xref += String(format: "%010d 00000 n \n", offset) }
    xref += "trailer\n<< /Size 11 /Root 1 0 R /Encrypt 10 0 R /ID [<\(hex(fileID))> <\(hex(fileID))>] >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
    body += Array(xref.utf8)
    do {
        try Data(body).write(to: out("odd-permissions.pdf"))
    } catch {
        fatalError("write odd-permissions.pdf: \(error)")
    }
}

FileHandle.standardError.write(Data("fixtures written to \(outDir.path)\n".utf8))
