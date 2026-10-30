import Combine
import PSPDFKit
import PSPDFKitUI
import SwiftUI

/// Fill, check and sign one form. The PDF is on the left, the checklist on the right.
struct FormFillView: View {
    @EnvironmentObject private var store: PacketStore
    let form: PacketForm
    let onCompleted: () -> Void

    @State private var pageIndex: PageIndex = 0
    @State private var showMissing = false
    @State private var alert: AlertContent?
    @State private var signHint: String?
    @State private var isExporting = false
    @State private var events = PassthroughSubject<PDFView.ActionEvent, Never>()

    var body: some View {
        let document = store.document(for: form)
        let snapshot = store.snapshot(for: form)
        HStack(spacing: 0) {
            PDFView(document: document, pageIndex: $pageIndex, actionEventPublisher: events) { builder in
                builder.pageTransition = .scrollContinuous
                builder.scrollDirection = .vertical
                builder.pageMode = .single
                builder.spreadFitting = .fit
                builder.thumbnailBarMode = .none
                // A shared iPad in a branch must not keep a customer's signature.
                builder.signatureSavingStrategy = .neverSave
                builder.signatureCreationConfiguration = .init(availableModes: [.draw, .type])
            }
            .onDidTapOnAnnotation { _, annotation in
                // Returning true stops Nutrient from opening the signature UI.
                guard annotation is SignatureFormElement else { return false }
                return !allowSigning(snapshot: currentSnapshot())
            }
            .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            ChecklistPanel(
                form: form,
                snapshot: snapshot,
                showMissing: showMissing,
                signHint: signHint,
                isExporting: isExporting,
                onSelect: go(to:),
                onPrimaryAction: { primaryAction(currentSnapshot()) }
            )
            .frame(width: 340)
        }
        .navigationTitle(form.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $alert) { content in
            Alert(title: Text(content.title), message: Text(content.message), dismissButton: .default(Text("OK")))
        }
        .onAppear { store.refresh(form) }
        .onDisappear { store.save(form) }
        .onChange(of: snapshot.unsignedFields.count) { _, count in
            if count == 0 { signHint = nil }
        }
    }

    /// Ends the edit in progress, so that the value being typed counts, and reads the form again.
    private func currentSnapshot() -> FormSnapshot {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        store.refresh(form)
        return store.snapshot(for: form)
    }

    /// Required fields are checked before any signature is placed.
    private func allowSigning(snapshot: FormSnapshot) -> Bool {
        guard snapshot.isReadyToSign else {
            showMissing = true
            alert = AlertContent.missingFields(snapshot.missingRequired)
            if let first = snapshot.missingRequired.first { go(to: first) }
            return false
        }
        return true
    }

    private func primaryAction(_ snapshot: FormSnapshot) {
        if snapshot.isComplete {
            finish()
        } else if allowSigning(snapshot: snapshot), let field = snapshot.unsignedFields.first {
            go(to: field)
            signHint = "Tap the box \u{201C}\(field.label)\u{201D} on page \(field.pageIndex + 1) to sign."
        }
    }

    private func finish() {
        isExporting = true
        store.save(form)
        do {
            _ = try store.complete(form)
            isExporting = false
            onCompleted()
        } catch {
            isExporting = false
            alert = AlertContent(title: "The form could not be saved", message: error.localizedDescription)
        }
    }

    private func go(to field: FieldStatus) {
        events.send(.setPageIndexWithHighlights(field.pageIndex, [field.rect]))
    }
}

struct AlertContent: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static func missingFields(_ fields: [FieldStatus]) -> AlertContent {
        let names = fields.prefix(8).map { field in
            "\u{2022} \(field.label)" + (field.problem.map { " (\($0))" } ?? "")
        }
        let more = fields.count > 8 ? "\n\u{2022} and \(fields.count - 8) more" : ""
        let count = fields.count == 1 ? "1 required field is" : "\(fields.count) required fields are"
        return AlertContent(
            title: "Complete the form before signing",
            message: "\(count) missing:\n" + names.joined(separator: "\n") + more
        )
    }
}

/// Progress, required fields, signatures and the next step.
private struct ChecklistPanel: View {
    let form: PacketForm
    let snapshot: FormSnapshot
    let showMissing: Bool
    let signHint: String?
    let isExporting: Bool
    let onSelect: (FieldStatus) -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(form.code).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: snapshot.progress)
                    .tint(snapshot.isComplete ? .green : .accentColor)
                Text("\(snapshot.requiredFilledCount) of \(snapshot.requiredFields.count) required fields \u{00B7} \(snapshot.signedCount) of \(snapshot.signatureFields.count) signatures")
                    .font(.subheadline)
                    .monospacedDigit()
                Button(action: onPrimaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isExporting)
                .accessibilityIdentifier("primary-action")
                if let signHint {
                    Label(signHint, systemImage: "hand.point.up.left")
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }
            }
            .padding()

            List {
                Section("Required fields") {
                    ForEach(snapshot.requiredFields) { field in
                        FieldRow(field: field, flagMissing: showMissing)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(field) }
                    }
                }
                Section("Signatures") {
                    ForEach(snapshot.signatureFields) { field in
                        FieldRow(field: field, flagMissing: showMissing && snapshot.isReadyToSign)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(field) }
                    }
                }
                let optional = snapshot.fields.filter { !$0.isRequired }
                if !optional.isEmpty {
                    Section("Optional fields") {
                        ForEach(optional) { field in
                            FieldRow(field: field, flagMissing: false)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(field) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var primaryTitle: String {
        if snapshot.isComplete { return isExporting ? "Saving\u{2026}" : "Finish and share" }
        return snapshot.isReadyToSign ? "Sign" : "Check form and sign"
    }

    private var primarySymbol: String {
        if snapshot.isComplete { return "checkmark.seal" }
        return snapshot.isReadyToSign ? "signature" : "checklist"
    }
}

private struct FieldRow: View {
    let field: FieldStatus
    let flagMissing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .foregroundStyle(flagMissing && !field.isFilled ? Color.red : Color.primary)
                if let problem = field.problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                } else if field.kind == .signature {
                    Text(field.isFilled ? "Signed" : "Not signed").font(.caption).foregroundStyle(.secondary)
                } else if field.isFilled, field.kind != .checkBox {
                    Text(field.value.display).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text("p. \(field.pageIndex + 1)").font(.caption2).foregroundStyle(.tertiary)
        }
        .font(.subheadline)
    }

    private var symbol: String {
        if field.isFilled { return "checkmark.circle.fill" }
        return flagMissing ? "exclamationmark.circle.fill" : "circle"
    }

    private var color: Color {
        if field.isFilled { return .green }
        return flagMissing ? .red : .secondary
    }
}
