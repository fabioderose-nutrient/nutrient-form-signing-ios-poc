import Foundation
import PSPDFKit

/// The state of one form field, read from the PDF with the Nutrient form API.
struct FieldStatus: Identifiable, Hashable {
    enum Kind: String, Codable {
        case text, date, checkBox, radio, choice, signature
    }

    let id: String
    let label: String
    let kind: Kind
    let isRequired: Bool
    let value: FieldValue
    let isFilled: Bool
    /// Why a filled value is not accepted, for example a date that cannot be read.
    let problem: String?
    let pageIndex: PageIndex
    let rect: CGRect
}

/// A field value as written to the JSON export.
enum FieldValue: Hashable, Codable {
    case text(String)
    case bool(Bool)
    case none

    var display: String {
        switch self {
        case .text(let text): return text
        case .bool(let value): return value ? "Yes" : "No"
        case .none: return ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .bool(let value): try container.encode(value)
        case .none: try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }
}

/// Progress of a form: which required fields are filled and which signatures are present.
struct FormSnapshot: Hashable {
    let fields: [FieldStatus]

    static let empty = FormSnapshot(fields: [])

    var requiredFields: [FieldStatus] { fields.filter { $0.isRequired && $0.kind != .signature } }
    var missingRequired: [FieldStatus] { requiredFields.filter { !$0.isFilled } }
    var signatureFields: [FieldStatus] { fields.filter { $0.kind == .signature } }
    var unsignedFields: [FieldStatus] { signatureFields.filter { !$0.isFilled } }

    var requiredFilledCount: Int { requiredFields.count - missingRequired.count }
    var signedCount: Int { signatureFields.count - unsignedFields.count }

    /// Every required field is filled: the form can be signed.
    var isReadyToSign: Bool { missingRequired.isEmpty }
    /// Ready to sign and every signature field carries a signature.
    var isComplete: Bool { isReadyToSign && unsignedFields.isEmpty && !signatureFields.isEmpty }
    var hasInput: Bool { fields.contains { $0.isFilled } }

    /// Progress from 0 to 1. Each required field and each signature counts as one step.
    var progress: Double {
        let total = requiredFields.count + signatureFields.count
        guard total > 0 else { return 0 }
        return Double(requiredFilledCount + signedCount) / Double(total)
    }
}

enum FormInspector {
    static let dateFormat = "yyyy-MM-dd"

    /// Reads every form field of the document.
    static func snapshot(of document: Document) -> FormSnapshot {
        guard let formFields = document.formParser?.formFields else { return .empty }
        let fields = formFields.compactMap(status(of:))
        let sorted = fields.sorted { a, b in
            if a.pageIndex != b.pageIndex { return a.pageIndex < b.pageIndex }
            // PDF coordinates grow upwards: higher on the page means a larger maxY.
            if abs(a.rect.maxY - b.rect.maxY) > 4 { return a.rect.maxY > b.rect.maxY }
            return a.rect.minX < b.rect.minX
        }
        return FormSnapshot(fields: sorted)
    }

    private static func status(of field: PDFFormField) -> FieldStatus? {
        guard let name = field.fullyQualifiedName ?? field.name,
              let widget = field.annotations.first else { return nil }
        let label = (field.alternateFieldName?.isEmpty == false ? field.alternateFieldName : nil) ?? name
        let required = field.isRequired

        var kind: FieldStatus.Kind
        var value: FieldValue = .none
        var filled = false
        var problem: String?

        switch field.type {
        case .text:
            let text = (field.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isDate = (widget as? TextFieldFormElement)?.inputFormat == .date
            kind = isDate ? .date : .text
            if !text.isEmpty {
                value = .text(text)
                filled = true
                if isDate && parseDate(text) == nil {
                    filled = false
                    problem = "Use the format YYYY-MM-DD"
                }
            }
        case .checkBox:
            kind = .checkBox
            let checked = (field as? ButtonFormField).map { button in
                field.annotations.contains { button.isSelected($0) }
            } ?? false
            value = .bool(checked)
            filled = checked
        case .radioButton:
            kind = .radio
            if let button = field as? ButtonFormField,
               let selected = field.annotations.first(where: { button.isSelected($0) }) {
                let state = button.onState(forButton: selected) ?? (field.value as? String) ?? ""
                value = .text(state)
                filled = !state.isEmpty && state != "Off"
            }
        case .comboBox, .listBox:
            kind = .choice
            if let text = field.value as? String, !text.isEmpty {
                value = .text(text)
                filled = true
            } else if let list = field.value as? [String], !list.isEmpty {
                value = .text(list.joined(separator: ", "))
                filled = true
            }
        case .signature:
            kind = .signature
            if let element = widget as? SignatureFormElement {
                filled = element.isSigned || element.overlappingSignatureAnnotation != nil
            }
            value = .bool(filled)
        default:
            return nil
        }

        return FieldStatus(
            id: name,
            label: label,
            kind: kind,
            isRequired: required || kind == .signature,
            value: value,
            isFilled: filled,
            problem: problem,
            pageIndex: widget.pageIndex,
            rect: widget.boundingBox
        )
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        formatter.isLenient = false
        return formatter.date(from: text)
    }
}
