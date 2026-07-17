// Output.swift - stdout/stderr writers, JSON emission, and text-output helper.
// Diagnostics go to stderr; payload (text, JSON) goes to stdout, never mixed.

import Foundation

func writeOut(_ s: String) {
    FileHandle.standardOutput.write(Data(s.utf8))
}

func writeErr(_ s: String) {
    FileHandle.standardError.write(Data(s.utf8))
}

// Print verb help to stdout (help is data the user asked for, not a diagnostic).
func printUsage(_ text: String) {
    let body = text.hasSuffix("\n") ? text : text + "\n"
    FileHandle.standardOutput.write(Data(body.utf8))
}

// Encode a Codable value to a pretty JSON string (sorted keys, ISO 8601 dates).
// Shared by the --json verbs and the MCP tools.
func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        throw PDFUtilError.processing("failed to encode JSON output")
    }
    return string
}

// Encode a Codable result as pretty JSON on stdout with a trailing newline.
func emitJSON<T: Encodable>(_ value: T) throws {
    writeOut(try encodeJSONString(value) + "\n")
}

// Write a text payload to stdout, or to a file under the overwrite policy
// (refuse an existing file unless force). A single trailing newline is ensured.
func writeTextOutput(_ text: String, to path: String?, force: Bool) throws {
    var body = text
    if !body.hasSuffix("\n") { body += "\n" }

    guard let path = path else {
        writeOut(body)
        return
    }
    if FileManager.default.fileExists(atPath: path) && !force {
        throw PDFUtilError.processing("output exists: \(path) (use --force to overwrite)")
    }
    do {
        try body.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        throw PDFUtilError.processing("failed to write output: \(path)")
    }
}
