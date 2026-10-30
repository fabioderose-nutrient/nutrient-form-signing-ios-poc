import Combine
import Foundation
import PSPDFKit

/// Where a form stands in the packet.
enum FormStatus: Equatable {
    case notStarted
    case inProgress
    case readyToSign
    case signed
    case completed

    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .inProgress: return "In progress"
        case .readyToSign: return "Ready to sign"
        case .signed: return "Signed"
        case .completed: return "Completed"
        }
    }
}

/// Keeps the working copy of each form, its progress and the completed files.
///
/// Working copies live in Application Support. The completed PDFs and JSON files are
/// written to Documents/Completed, which the Files app shows under On My iPad.
@MainActor
final class PacketStore: ObservableObject {
    @Published private(set) var snapshots: [String: FormSnapshot] = [:]
    @Published private(set) var completions: [String: CompletionRecord] = [:]

    let forms = PacketCatalog.forms
    let documentsRoot: URL
    private let workingFolder: URL
    private let stateURL: URL
    private var documents: [String: Document] = [:]
    private var observers: [NSObjectProtocol] = []
    private var pendingRefresh: [String: DispatchWorkItem] = [:]

    init() {
        let fileManager = FileManager.default
        documentsRoot = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Packet", isDirectory: true)
        workingFolder = support.appendingPathComponent("Working", isDirectory: true)
        stateURL = support.appendingPathComponent("completions.json")
        try? fileManager.createDirectory(at: workingFolder, withIntermediateDirectories: true)

        prepareWorkingCopies()
        loadCompletions()
        forms.forEach(refresh)
        observeAnnotationChanges()
    }

    // MARK: Documents

    func document(for form: PacketForm) -> Document {
        if let document = documents[form.id] { return document }
        let document = Document(url: workingURL(for: form))
        document.annotationSaveMode = .embedded
        documents[form.id] = document
        return document
    }

    func snapshot(for form: PacketForm) -> FormSnapshot {
        snapshots[form.id] ?? .empty
    }

    func status(for form: PacketForm) -> FormStatus {
        if completions[form.id] != nil { return .completed }
        let snapshot = snapshot(for: form)
        if snapshot.isComplete { return .signed }
        if snapshot.isReadyToSign && !snapshot.requiredFields.isEmpty { return .readyToSign }
        return snapshot.hasInput ? .inProgress : .notStarted
    }

    var completedCount: Int { forms.filter { completions[$0.id] != nil }.count }

    func refresh(_ form: PacketForm) {
        snapshots[form.id] = FormInspector.snapshot(of: document(for: form))
    }

    func save(_ form: PacketForm) {
        guard let document = documents[form.id], document.hasDirtyAnnotations else { return }
        do {
            try document.save()
        } catch {
            print("Saving \(form.fileName) failed: \(error.localizedDescription)")
        }
    }

    func saveAll() {
        forms.forEach(save)
    }

    // MARK: Completion

    /// Flattens the form, writes the JSON and remembers the result.
    func complete(_ form: PacketForm) throws -> CompletionRecord {
        let stamp = Self.folderStamp.string(from: Date())
        let folder = documentsRoot
            .appendingPathComponent("Completed", isDirectory: true)
            .appendingPathComponent("\(stamp)-\(form.id)", isDirectory: true)
        let record = try FormExporter.export(
            form: form, document: document(for: form), into: folder, documentsRoot: documentsRoot
        )
        completions[form.id] = record
        storeCompletions()
        refresh(form)
        return record
    }

    func fileURL(_ relativePath: String) -> URL {
        documentsRoot.appendingPathComponent(relativePath)
    }

    /// Starts a new packet: fresh blank forms. Files already exported stay in Documents/Completed.
    func reset() {
        documents.removeAll()
        completions.removeAll()
        storeCompletions()
        for form in forms {
            try? FileManager.default.removeItem(at: workingURL(for: form))
        }
        prepareWorkingCopies()
        forms.forEach(refresh)
    }

    // MARK: Private

    private func workingURL(for form: PacketForm) -> URL {
        workingFolder.appendingPathComponent(form.fileName)
    }

    private func prepareWorkingCopies() {
        let fileManager = FileManager.default
        for form in forms {
            let target = workingURL(for: form)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            let name = (form.fileName as NSString).deletingPathExtension
            guard let source = Bundle.main.url(forResource: name, withExtension: "pdf") else {
                assertionFailure("Missing bundled form \(form.fileName)")
                continue
            }
            try? fileManager.copyItem(at: source, to: target)
        }
    }

    private func observeAnnotationChanges() {
        let names: [Notification.Name] = [.PSPDFAnnotationChanged, .PSPDFAnnotationsAdded, .PSPDFAnnotationsRemoved]
        for name in names {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let annotations: [Annotation]
                if let annotation = note.object as? Annotation {
                    annotations = [annotation]
                } else {
                    annotations = note.object as? [Annotation] ?? []
                }
                MainActor.assumeIsolated {
                    self?.scheduleRefresh(for: annotations)
                }
            }
            observers.append(observer)
        }
    }

    /// Refreshes the progress of the forms whose annotations changed, at most every 0.3 s.
    private func scheduleRefresh(for annotations: [Annotation]) {
        for form in forms {
            guard let document = documents[form.id],
                  annotations.isEmpty || annotations.contains(where: { $0.document === document }) else { continue }
            pendingRefresh[form.id]?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh(form) }
            pendingRefresh[form.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func loadCompletions() {
        guard let data = try? Data(contentsOf: stateURL),
              let records = try? JSONDecoder().decode([String: CompletionRecord].self, from: data) else { return }
        completions = records
    }

    private func storeCompletions() {
        if let data = try? JSONEncoder().encode(completions) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private static let folderStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
