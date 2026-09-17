// Core/FormsCore.swift - inspect and fill AcroForm fields (structure-preserving).
// A field is a page annotation of type "Widget"; text/button/choice widgets carry
// a value we can read and set. Filling sets the widget value in place; an
// optional flatten burns the values into the page content.

import Foundation
import PDFKit

// One form field, as listed (human or --json). `value` is a string in every case
// ("on"/"off" for a button); `choices` is present only for choice fields.
struct FormField: Codable {
    let page: Int       // 1-based
    let name: String
    let kind: String    // text | button | choice | unknown
    let value: String
    let choices: [String]?
    let readOnly: Bool
}

private func kindName(_ type: PDFAnnotationWidgetSubtype) -> String {
    switch type {
    case .text: return "text"
    case .button: return "button"
    case .choice: return "choice"
    default: return "unknown"
    }
}

// Collect every widget annotation across all pages, in page then on-page order.
func gatherFormFields(_ doc: PDFDocument) -> [FormField] {
    var fields: [FormField] = []
    for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i) else { continue }
        for annotation in page.annotations where annotation.type == "Widget" {
            let type = annotation.widgetFieldType
            let value: String
            if type == .button {
                value = annotation.buttonWidgetState == .onState ? "on" : "off"
            } else {
                value = annotation.widgetStringValue ?? ""
            }
            fields.append(FormField(
                page: i + 1,
                name: annotation.fieldName ?? "",
                kind: kindName(type),
                value: value,
                choices: type == .choice ? annotation.choices : nil,
                readOnly: annotation.isReadOnly))
        }
    }
    return fields
}

func formatFormFields(_ fields: [FormField]) -> String {
    guard !fields.isEmpty else { return "(no form fields)\n" }
    var s = ""
    for f in fields {
        var line = "page \(f.page): \(f.name) (\(f.kind)) = \(f.value)"
        if let choices = f.choices, !choices.isEmpty {
            line += " [choices: \(choices.joined(separator: ", "))]"
        }
        if f.readOnly { line += " (read-only)" }
        s += line + "\n"
    }
    return s
}

// Read a {fieldName: value} JSON file and apply it to the document's widgets
// (the forms verb's --fill path).
func fillForm(doc: PDFDocument, dataPath: String) throws {
    guard let data = FileManager.default.contents(atPath: dataPath) else {
        throw PDFUtilError.usage("cannot read fill data: \(dataPath)")
    }
    let object = try? JSONSerialization.jsonObject(with: data)
    guard let values = object as? [String: Any] else {
        throw PDFUtilError.usage("fill data must be a JSON object of fieldName: value")
    }
    try applyFormValues(doc: doc, values: values)
}

// Apply a {fieldName: value} dictionary to the document's widgets. A text/choice
// value must be a string; a button value must be a bool. An unknown field name
// is a processing error that lists the available names.
//
// A bool sets every widget that shares the field name to that on/off state, which
// is exactly right for a single checkbox. A multi-widget radio group is not
// individually selectable this way (a `true` would turn every option on); such
// groups are out of scope.
func applyFormValues(doc: PDFDocument, values: [String: Any]) throws {
    try requirePermission(doc.allowsFormFieldEntry, "filling in form fields", in: doc)
    // Index widgets by field name (a field may span several widgets, e.g. radios).
    var widgets: [String: [PDFAnnotation]] = [:]
    for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i) else { continue }
        for annotation in page.annotations where annotation.type == "Widget" {
            if let name = annotation.fieldName {
                widgets[name, default: []].append(annotation)
            }
        }
    }

    for (name, value) in values {
        guard let targets = widgets[name] else {
            let available = widgets.keys.sorted().joined(separator: ", ")
            throw PDFUtilError.processing("unknown field '\(name)' (available: \(available))")
        }
        for annotation in targets {
            if annotation.widgetFieldType == .button {
                // Strictly a JSON true/false: an NSNumber 0/1 bridges to Bool,
                // but accepting it would blur the string/bool distinction the
                // field kinds rely on.
                guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else {
                    throw PDFUtilError.usage("field '\(name)' is a button; value must be true or false")
                }
                annotation.buttonWidgetState = n.boolValue ? .onState : .offState
            } else {
                guard let string = value as? String else {
                    throw PDFUtilError.usage("field '\(name)' is a text/choice field; value must be a string")
                }
                annotation.widgetStringValue = string
            }
        }
    }
}

// Save after a fill/flatten. Filling alone is structure-preserving; --flatten
// burns the widgets' appearances into the page and drops the interactive fields.
func saveForm(doc: PDFDocument, output: String?, force: Bool,
              inPlaceOf path: String, flatten: Bool, password: String?) throws {
    let options: [PDFDocumentWriteOption: Any] = flatten ? [.burnInAnnotationsOption: true] : [:]
    try savePDF(doc, to: output, writeOptions: options, force: force, inPlaceOf: path,
                password: password)
}
