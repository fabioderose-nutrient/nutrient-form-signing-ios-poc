import PSPDFKit
import PSPDFKitUI
import SwiftUI

/// A completed form: the flattened PDF, the checks run on it, the JSON and the share sheet.
struct CompletedFormView: View {
    let form: PacketForm
    let record: CompletionRecord
    let pdfURL: URL
    let jsonURL: URL

    @State private var document: PSPDFKit.Document
    @State private var pageIndex: PageIndex
    @State private var json = ""

    init(form: PacketForm, record: CompletionRecord, pdfURL: URL, jsonURL: URL) {
        self.form = form
        self.record = record
        self.pdfURL = pdfURL
        self.jsonURL = jsonURL
        let document = PSPDFKit.Document(url: pdfURL)
        _document = State(initialValue: document)
        // Open on the last page, where the signatures are.
        _pageIndex = State(initialValue: document.pageCount > 0 ? document.pageCount - 1 : 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            PDFView(document: document, pageIndex: $pageIndex) { builder in
                builder.pageTransition = .scrollContinuous
                builder.scrollDirection = .vertical
                builder.pageMode = .single
                builder.thumbnailBarMode = .none
                builder.editableAnnotationTypes = []
            }
            .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Completed", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text(record.completedAt.formatted(date: .long, time: .shortened))
                            .foregroundStyle(.secondary)
                        ShareLink(items: [pdfURL, jsonURL]) {
                            Label("Share PDF and JSON", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("share")
                    }
                    .padding(.vertical, 4)
                }
                Section("Checked in the flattened PDF") {
                    CheckRow(ok: record.formFieldsLeft == 0, text: "\(record.formFieldsLeft) form fields left")
                    CheckRow(ok: record.annotationsLeft == 0, text: "\(record.annotationsLeft) annotations left, the signature is page content")
                    CheckRow(ok: record.textValuesFound == record.textValuesChecked,
                             text: "\(record.textValuesFound) of \(record.textValuesChecked) typed values found in the page text")
                }
                Section("Files") {
                    Label(pdfURL.lastPathComponent, systemImage: "doc.richtext")
                    Label(jsonURL.lastPathComponent, systemImage: "curlybraces")
                }
                .font(.subheadline)
                Section("Field values (JSON)") {
                    Text(json)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .listStyle(.insetGrouped)
            .frame(width: 360)
        }
        .navigationTitle(form.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { json = Self.valuesPreview(jsonURL) }
    }

    /// The `values` object of the JSON, which is what a back office would import.
    private static func valuesPreview(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["values"],
              let pretty = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "" }
        return String(decoding: pretty, as: UTF8.self)
    }
}

private struct CheckRow: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? .green : .red)
        }
        .font(.subheadline)
    }
}
