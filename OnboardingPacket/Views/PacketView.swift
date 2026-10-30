import SwiftUI

enum Route: Hashable {
    case fill(String)
    case completed(String)
}

/// The packet: every form with its progress.
struct PacketView: View {
    @EnvironmentObject private var store: PacketStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    @State private var confirmReset = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    PacketSummary()
                }
                Section {
                    ForEach(store.forms) { form in
                        NavigationLink(value: route(for: form)) {
                            FormRow(form: form)
                        }
                        .accessibilityIdentifier("form-\(form.id)")
                    }
                } header: {
                    Text("Forms")
                } footer: {
                    Text("Fill each form, check it, then sign. Completed forms are saved as a flattened PDF and a JSON file of the field values in Files, On My iPad, Onboarding Packet, Completed.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Onboarding packet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New packet", systemImage: "arrow.counterclockwise") { confirmReset = true }
                        .labelStyle(.titleAndIcon)
                }
            }
            .confirmationDialog("Start a new packet?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Clear all forms", role: .destructive) { store.reset() }
            } message: {
                Text("All forms go back to blank. Files already completed stay in the Completed folder.")
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .fill(let id):
                    if let form = store.forms.first(where: { $0.id == id }) {
                        FormFillView(form: form) { path = [.completed(id)] }
                    }
                case .completed(let id):
                    if let form = store.forms.first(where: { $0.id == id }),
                       let record = store.completions[id] {
                        CompletedFormView(
                            form: form,
                            record: record,
                            pdfURL: store.fileURL(record.pdfPath),
                            jsonURL: store.fileURL(record.jsonPath)
                        )
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveAll() }
        }
    }

    private func route(for form: PacketForm) -> Route {
        store.completions[form.id] != nil ? .completed(form.id) : .fill(form.id)
    }
}

private struct PacketSummary: View {
    @EnvironmentObject private var store: PacketStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PacketCatalog.title)
                .font(.title2.weight(.semibold))
            Text("\(store.completedCount) of \(store.forms.count) forms completed")
                .foregroundStyle(.secondary)
            ProgressView(value: Double(store.completedCount), total: Double(store.forms.count))
                .tint(.accentColor)
            if LicenseKey.isTrial {
                Text("Nutrient trial mode: pages show a watermark.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

/// One form of the packet with its progress.
struct FormRow: View {
    @EnvironmentObject private var store: PacketStore
    let form: PacketForm

    var body: some View {
        let snapshot = store.snapshot(for: form)
        let status = store.status(for: form)
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: form.symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(form.title).font(.headline)
                    Spacer()
                    StatusBadge(status: status)
                }
                Text(form.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: status == .completed ? 1 : snapshot.progress)
                    .tint(status == .completed || status == .signed ? .green : .accentColor)
                Text(detail(snapshot, status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 8)
    }

    private func detail(_ snapshot: FormSnapshot, _ status: FormStatus) -> String {
        let fields = "\(snapshot.requiredFilledCount) of \(snapshot.requiredFields.count) required fields"
        let signatures = "\(snapshot.signedCount) of \(snapshot.signatureFields.count) signatures"
        if status == .completed, let record = store.completions[form.id] {
            return "\(form.code) · \(fields) · \(signatures) · completed \(record.completedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(form.code) · \(fields) · \(signatures)"
    }
}

struct StatusBadge: View {
    let status: FormStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .notStarted: return .secondary
        case .inProgress: return .orange
        case .readyToSign: return .blue
        case .signed, .completed: return .green
        }
    }
}
