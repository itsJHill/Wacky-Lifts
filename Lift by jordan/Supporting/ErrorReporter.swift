import Foundation

/// Lightweight ring-buffer log for non-fatal errors and warnings. Keeps the
/// most recent N entries in memory so a future Settings screen can surface
/// them; also mirrors each entry to stdout so they remain visible in Xcode.
///
/// Intentionally simple: no threading primitives (callers are main-thread),
/// no persistence, no notifications. Upgrade as consumers appear.
final class ErrorReporter {
    static let shared = ErrorReporter()

    struct Entry {
        let timestamp: Date
        let source: String
        let message: String
        let errorDescription: String?
    }

    private let capacity = 100
    private(set) var entries: [Entry] = []

    private init() {}

    /// Record a non-fatal failure. `source` is a short tag (e.g. "WeightLogStore.save")
    /// so the Settings debug view can group entries. `error` is optional; pass it
    /// when you caught one, omit when logging a post-condition violation.
    func report(_ message: String, source: String, error: Error? = nil) {
        let entry = Entry(
            timestamp: Date(),
            source: source,
            message: message,
            errorDescription: error.map { String(describing: $0) }
        )
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        if let error {
            print("[\(source)] \(message) — \(error)")
        } else {
            print("[\(source)] \(message)")
        }
    }

    func clear() {
        entries.removeAll()
    }
}
