import Foundation
import PSPDFKit

/// The JSON written next to the flattened PDF.
struct FormExport: Codable {
    struct FormInfo: Codable {
        let id: String
        let title: String
        let code: String
        let sourceFile: String
    }

    struct Field: Codable {
        let name: String
        let label: String
        let type: FieldStatus.Kind
        let required: Bool
        let page: Int
        let value: FieldValue
    }

    struct Signature: Codable {
        let name: String
        let label: String
        let page: Int
        let signed: Bool
    }

    struct Output: Codable {
        let pdf: String
        let flattened: Bool
        let formFieldsLeft: Int
        let annotationsLeft: Int
        let textValuesFoundInPdf: Int
        let textValuesChecked: Int
    }

    let packet: String
    let form: FormInfo
    let completedAt: String
    let sdk: String
    /// Field name to value, ready for a back-office import.
    let values: [String: FieldValue]
    let fields: [Field]
    let signatures: [Signature]
    let output: Output
}

/// Result of a completed form: the two files and what was checked in the PDF.
struct CompletionRecord: Codable, Hashable {
    let formId: String
    let completedAt: Date
    /// Paths relative to the app's Documents folder.
    let pdfPath: String
    let jsonPath: String
    let formFieldsLeft: Int
    let annotationsLeft: Int
    let textValuesFound: Int
    let textValuesChecked: Int

    var isVerified: Bool { formFieldsLeft == 0 && annotationsLeft == 0 && textValuesFound == textValuesChecked }
}

enum ExportError: LocalizedError {
    case notComplete
    case processorUnavailable

    var errorDescription: String? {
        switch self {
        case .notComplete: return "The form is not complete. Fill the required fields and sign it first."
        case .processorUnavailable: return "The PDF processor could not be configured for this document."
        }
    }
}

enum FormExporter {
    /// Flattens the filled and signed form into a new PDF and writes the field values as JSON.
    static func export(form: PacketForm, document: Document, into folder: URL, documentsRoot: URL) throws -> CompletionRecord {
        let snapshot = FormInspector.snapshot(of: document)
        guard snapshot.isComplete else { throw ExportError.notComplete }

        try document.save()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let baseName = (form.fileName as NSString).deletingPathExtension
        let pdfURL = folder.appendingPathComponent("\(baseName)-completed.pdf")
        let jsonURL = folder.appendingPathComponent("\(baseName)-values.json")

        // 1. Flatten: form fields and the signature annotations become page content.
        guard let configuration = Processor.Configuration(document: document) else {
            throw ExportError.processorUnavailable
        }
        configuration.modifyAnnotations(ofTypes: .all, change: .flatten)
        let processor = Processor(configuration: configuration, securityOptions: nil)
        try processor.write(toFileURL: pdfURL)

        // 2. Check the output: no field or annotation left, and the typed values are now page text.
        let output = Document(url: pdfURL)
        let fieldsLeft = output.formParser?.formFields?.count ?? 0
        let annotationsLeft = output.allAnnotations(of: .all).values.reduce(0) { $0 + $1.count }
        var pageText: [PageIndex: String] = [:]
        let textFields = snapshot.fields.filter {
            ($0.kind == .text || $0.kind == .date) && !$0.value.display.isEmpty
        }
        var found = 0
        for field in textFields {
            if pageText[field.pageIndex] == nil {
                pageText[field.pageIndex] = output.textParserForPage(at: field.pageIndex)?.text ?? ""
            }
            if normalized(pageText[field.pageIndex] ?? "").contains(normalized(field.value.display)) {
                found += 1
            }
        }

        // 3. JSON with the values, the signatures and the checks.
        let completedAt = Date()
        let export = FormExport(
            packet: PacketCatalog.title,
            form: .init(id: form.id, title: form.title, code: form.code, sourceFile: form.fileName),
            completedAt: ISO8601DateFormatter().string(from: completedAt),
            sdk: SDK.versionString,
            values: Dictionary(uniqueKeysWithValues: snapshot.fields
                .filter { $0.kind != .signature }
                .map { ($0.id, $0.value) }),
            fields: snapshot.fields.filter { $0.kind != .signature }.map {
                .init(name: $0.id, label: $0.label, type: $0.kind, required: $0.isRequired,
                      page: Int($0.pageIndex) + 1, value: $0.value)
            },
            signatures: snapshot.signatureFields.map {
                .init(name: $0.id, label: $0.label, page: Int($0.pageIndex) + 1, signed: $0.isFilled)
            },
            output: .init(pdf: pdfURL.lastPathComponent, flattened: true, formFieldsLeft: fieldsLeft,
                          annotationsLeft: annotationsLeft, textValuesFoundInPdf: found,
                          textValuesChecked: textFields.count)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(export).write(to: jsonURL, options: .atomic)

        return CompletionRecord(
            formId: form.id,
            completedAt: completedAt,
            pdfPath: relativePath(of: pdfURL, to: documentsRoot),
            jsonPath: relativePath(of: jsonURL, to: documentsRoot),
            formFieldsLeft: fieldsLeft,
            annotationsLeft: annotationsLeft,
            textValuesFound: found,
            textValuesChecked: textFields.count
        )
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private static func relativePath(of url: URL, to root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : url.lastPathComponent
    }
}
