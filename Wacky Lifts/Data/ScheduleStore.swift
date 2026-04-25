import Foundation

final class ScheduleStore {
    static let shared = ScheduleStore()

    static let scheduleDidChangeNotification = Notification.Name("ScheduleStore.scheduleDidChange")

    private let userDefaults = UserDefaults.standard
    private let scheduleKey = "weekly_schedule"
    private let previousScheduleKey = "weekly_schedule_previous"
    private let weekIdentifierKey = "schedule_week_identifier"

    private(set) var schedule: [Weekday: [WorkoutTemplate]] = {
        var map: [Weekday: [WorkoutTemplate]] = [:]
        Weekday.allCases.forEach { map[$0] = [] }
        return map
    }()

    /// Template IDs from disk that didn't resolve against the current library
    /// (e.g. a partial backup restore where the schedule loaded before the
    /// workout library). Kept so they can be re-resolved the next time the
    /// library changes and so they round-trip through `save()` without being
    /// silently dropped.
    private var pendingIds: [Weekday: [UUID]] = [:]

    private init() {
        loadSchedule()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryChange),
            name: WorkoutLibraryStore.libraryDidChangeNotification,
            object: nil
        )
    }

    var availableWorkouts: [WorkoutTemplate] {
        WorkoutLibraryStore.shared.templates
    }

    func workouts(for day: Weekday) -> [WorkoutTemplate] {
        schedule[day] ?? []
    }

    func add(_ template: WorkoutTemplate, to day: Weekday) {
        var dayWorkouts = schedule[day] ?? []
        dayWorkouts.append(template)
        schedule[day] = dayWorkouts
        save()
        notifyChange()
    }

    func remove(templateId: WorkoutTemplate.ID, from day: Weekday) {
        guard var dayWorkouts = schedule[day] else { return }
        dayWorkouts.removeAll { $0.id == templateId }
        schedule[day] = dayWorkouts
        save()
        notifyChange()
    }

    func clear(day: Weekday) {
        schedule[day] = []
        save()
        notifyChange()
    }

    func replace(day: Weekday, with templates: [WorkoutTemplate]) {
        schedule[day] = templates
        save()
        notifyChange()
    }

    func move(day: Weekday, from sourceIndex: Int, to destinationIndex: Int) {
        guard var dayWorkouts = schedule[day],
            sourceIndex >= 0,
            sourceIndex < dayWorkouts.count,
            destinationIndex >= 0,
            destinationIndex < dayWorkouts.count
        else { return }

        let workout = dayWorkouts.remove(at: sourceIndex)
        dayWorkouts.insert(workout, at: destinationIndex)
        schedule[day] = dayWorkouts
        save()
        notifyChange()
    }

    @objc private func handleLibraryChange() {
        refreshFromLibrary()
    }

    /// Force refresh all scheduled workouts from the library to get latest data.
    /// Only updates the schedule — does NOT delete historical logs, PRs, or snapshots.
    /// Also retries any previously-pending template IDs that couldn't be resolved
    /// at load time; this is the recovery path for out-of-order backup imports.
    func refreshFromLibrary() {
        let library = WorkoutLibraryStore.shared
        var updated: [Weekday: [WorkoutTemplate]] = [:]
        var stillPending: [Weekday: [UUID]] = [:]
        Weekday.allCases.forEach { day in
            let existing = schedule[day] ?? []
            var mapped = existing.compactMap { library.template(withId: $0.id) }

            if let pending = pendingIds[day] {
                var unresolved: [UUID] = []
                for id in pending {
                    if let template = library.template(withId: id) {
                        mapped.append(template)
                    } else {
                        unresolved.append(id)
                    }
                }
                if !unresolved.isEmpty {
                    stillPending[day] = unresolved
                }
            }

            updated[day] = mapped
        }
        schedule = updated
        pendingIds = stillPending
        save()
        notifyChange()
    }

    // MARK: - Persistence

    private func currentWeekIdentifier() -> String {
        AppDateCoding.weekIdentifier(for: Date())
    }

    private func loadSchedule() {
        let currentWeek = currentWeekIdentifier()
        let savedWeek = userDefaults.string(forKey: weekIdentifierKey)

        // If it's a new week, clear the schedule
        if savedWeek != currentWeek {
            clearAllData()
            userDefaults.set(currentWeek, forKey: weekIdentifierKey)
            return
        }

        // Load saved schedule
        guard let data = userDefaults.data(forKey: scheduleKey) else { return }

        do {
            let savedSchedule = try JSONDecoder().decode(SavedSchedule.self, from: data)
            let library = WorkoutLibraryStore.shared

            var loadedSchedule: [Weekday: [WorkoutTemplate]] = [:]
            var pending: [Weekday: [UUID]] = [:]
            Weekday.allCases.forEach { loadedSchedule[$0] = [] }

            for (weekdayRaw, workoutIds) in savedSchedule.weekdayWorkouts {
                guard let weekday = Weekday(rawValue: weekdayRaw) else { continue }
                var resolved: [WorkoutTemplate] = []
                var unresolved: [UUID] = []
                for id in workoutIds {
                    if let template = library.template(withId: id) {
                        resolved.append(template)
                    } else {
                        unresolved.append(id)
                    }
                }
                loadedSchedule[weekday] = resolved
                if !unresolved.isEmpty {
                    pending[weekday] = unresolved
                    ErrorReporter.shared.report(
                        "\(unresolved.count) unresolved template ID(s) on \(weekday) — will retry on next library change.",
                        source: "ScheduleStore.loadSchedule"
                    )
                }
            }

            schedule = loadedSchedule
            pendingIds = pending
        } catch {
            ErrorReporter.shared.report("Failed to load schedule", source: "ScheduleStore.loadSchedule", error: error)
        }
    }

    private func save() {
        let currentWeek = currentWeekIdentifier()
        userDefaults.set(currentWeek, forKey: weekIdentifierKey)

        var weekdayWorkouts: [Int: [UUID]] = [:]
        for (weekday, workouts) in schedule {
            var ids = workouts.map { $0.id }
            // Preserve unresolved IDs so they survive save/reload and can be
            // reattached on the next library change.
            if let pending = pendingIds[weekday] {
                ids.append(contentsOf: pending)
            }
            weekdayWorkouts[weekday.rawValue] = ids
        }

        let savedSchedule = SavedSchedule(weekdayWorkouts: weekdayWorkouts)

        do {
            let data = try JSONEncoder().encode(savedSchedule)
            userDefaults.set(data, forKey: scheduleKey)
        } catch {
            ErrorReporter.shared.report("Failed to save schedule", source: "ScheduleStore.save", error: error)
        }
    }

    private func clearAllData() {
        // Archive the outgoing schedule before wiping, so a glitched clock or
        // ISO-week edge case that triggers an unexpected reset doesn't destroy
        // the user's data outright. The archive is overwritten each reset.
        if let outgoing = userDefaults.data(forKey: scheduleKey) {
            userDefaults.set(outgoing, forKey: previousScheduleKey)
        }
        var emptySchedule: [Weekday: [WorkoutTemplate]] = [:]
        Weekday.allCases.forEach { emptySchedule[$0] = [] }
        schedule = emptySchedule
        pendingIds = [:]
        userDefaults.removeObject(forKey: scheduleKey)
    }

    func resetAll() {
        clearAllData()
        notifyChange()
    }

    /// Re-read the schedule from UserDefaults. Called by `DataBackupManager`
    /// after import so the Schedule tab reflects the restored data without
    /// requiring an app relaunch.
    func reloadFromDisk() {
        loadSchedule()
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.scheduleDidChangeNotification, object: self)
    }
}

// MARK: - Persistence Model

private struct SavedSchedule: Codable {
    let weekdayWorkouts: [Int: [UUID]]
}
