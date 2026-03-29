import Foundation

final class WorkoutSnapshotStore {
    static let shared = WorkoutSnapshotStore()

    private let userDefaults = UserDefaults.standard
    private let snapshotsKey = "workout_snapshots"
    private let lastCleanupKey = "workout_snapshots_last_cleanup"

    private var snapshots: [String: WorkoutTemplate] {
        didSet {
            saveSnapshots()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {
        snapshots = [:]
        loadSnapshots()
        cleanupOldSnapshotsIfNeeded()
    }

    // MARK: - Key Generation

    private func key(for workoutId: UUID, on date: Date) -> String {
        let dateString = Self.dateFormatter.string(from: date)
        return "\(dateString)_\(workoutId.uuidString)"
    }

    // MARK: - Public API

    /// Write-once capture: only saves if no snapshot exists yet for this workout+date
    func captureIfNeeded(_ template: WorkoutTemplate, on date: Date) {
        let k = key(for: template.id, on: date)
        guard snapshots[k] == nil else { return }
        snapshots[k] = template
    }

    /// Retrieve a snapshot for a workout on a given date, or nil if none was captured
    func snapshot(for workoutId: UUID, on date: Date) -> WorkoutTemplate? {
        let k = key(for: workoutId, on: date)
        return snapshots[k]
    }

    /// Update all existing snapshots for a workout with the latest template data.
    /// Only replaces snapshots that already exist (preserves exercise IDs for completion/log matching).
    func updateSnapshots(for template: WorkoutTemplate) {
        let idSuffix = "_\(template.id.uuidString)"
        var updated = false
        for (k, _) in snapshots where k.hasSuffix(idSuffix) {
            snapshots[k] = template
            updated = true
        }
        // didSet handles persistence if any were updated
        _ = updated
    }

    /// Delete all snapshots for a workout (used when workout is fully unscheduled)
    func deleteSnapshots(for workoutId: UUID) {
        let idString = workoutId.uuidString
        let before = snapshots.count
        snapshots = snapshots.filter { !$0.key.hasSuffix("_\(idString)") }
        if snapshots.count != before {
            // didSet already saved
        }
    }

    /// Delete snapshot for a specific workout on a specific date
    func deleteSnapshot(for workoutId: UUID, on date: Date) {
        let k = key(for: workoutId, on: date)
        snapshots.removeValue(forKey: k)
    }

    /// Delete all snapshots for a specific date
    func deleteSnapshots(on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        let before = snapshots.count
        snapshots = snapshots.filter { !$0.key.hasPrefix(dateString) }
        if snapshots.count != before {
            // didSet already saved
        }
    }

    // MARK: - Persistence

    private func loadSnapshots() {
        guard let data = userDefaults.data(forKey: snapshotsKey) else { return }

        do {
            let decoded = try JSONDecoder().decode([String: WorkoutTemplate].self, from: data)
            snapshots = decoded
        } catch {
            print("Failed to load workout snapshots: \(error)")
        }
    }

    private func saveSnapshots() {
        do {
            let data = try JSONEncoder().encode(snapshots)
            userDefaults.set(data, forKey: snapshotsKey)
        } catch {
            print("Failed to save workout snapshots: \(error)")
        }
    }

    // MARK: - Cleanup (3-month retention, weekly check)

    private func cleanupOldSnapshotsIfNeeded() {
        let calendar = Calendar.current
        let today = Date()

        if let lastCleanup = userDefaults.object(forKey: lastCleanupKey) as? Date,
           let daysSinceCleanup = calendar.dateComponents([.day], from: lastCleanup, to: today).day,
           daysSinceCleanup < 7 {
            return
        }

        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: today) else { return }

        let oldCount = snapshots.count
        snapshots = snapshots.filter { key, _ in
            // Extract date from key (format: "yyyy-MM-dd_workoutId")
            let dateString = String(key.prefix(10))
            guard let date = Self.dateFormatter.date(from: dateString) else { return false }
            return date >= threeMonthsAgo
        }

        if snapshots.count != oldCount {
            print("Cleaned up \(oldCount - snapshots.count) old workout snapshots")
        }

        userDefaults.set(today, forKey: lastCleanupKey)
    }

    func resetAll() {
        snapshots = [:]
        userDefaults.removeObject(forKey: lastCleanupKey)
    }
}
