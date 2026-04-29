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

    /// Template IDs provided by the active program for the current week.
    /// These workout cells receive a left accent bar to distinguish them
    /// from user-added extras. Not persisted — recomputed on activation or
    /// week boundary.
    private(set) var programWorkoutIds: [Weekday: Set<UUID>] = {
        var map: [Weekday: Set<UUID>] = [:]
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

    func isProgramWorkout(_ templateId: WorkoutTemplate.ID, on day: Weekday) -> Bool {
        programWorkoutIds[day]?.contains(templateId) ?? false
    }

    /// Insert program workouts at the top of each day's schedule.
    /// Called by ProgramStore when a program is activated or week advances.
    func populateFromProgram(week: ProgramWeek) {
        // Clear existing program assignments
        clearProgramAssignments()

        for day in week.days {
            let library = WorkoutLibraryStore.shared
            let templates = day.workoutIds.compactMap { library.template(withId: $0) }
            guard !templates.isEmpty else { continue }

            var existing = schedule[day.weekday] ?? []
            // Split existing into program and extras (there shouldn't be program
            // workouts right now since we just cleared them, but be safe)
            let programIds = Set(day.workoutIds)
            let extras = existing.filter { !programIds.contains($0.id) }

            // Program workouts first, then extras
            schedule[day.weekday] = templates + extras
            programWorkoutIds[day.weekday] = Set(templates.map { $0.id })
        }

        save()
        notifyChange()
    }

    /// Remove all program-sourced workouts from the schedule.
    /// Extras added by the user are preserved.
    func clearProgramAssignments() {
        for (day, ids) in programWorkoutIds where !ids.isEmpty {
            var current = schedule[day] ?? []
            current.removeAll { ids.contains($0.id) }
            schedule[day] = current
        }
        programWorkoutIds = {
            var map: [Weekday: Set<UUID>] = [:]
            Weekday.allCases.forEach { map[$0] = [] }
            return map
        }()
        save()
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

    /// Merge extras below program workouts on a given day. If no program is active,
    /// behaves the same as replace.
    func mergeExtras(day: Weekday, with extras: [WorkoutTemplate]) {
        let programIds = programWorkoutIds[day] ?? []
        var current = schedule[day] ?? []

        if programIds.isEmpty {
            // No program active — just replace
            schedule[day] = extras
        } else {
            // Keep program workouts at top
            let programWorkouts = current.filter { programIds.contains($0.id) }
            schedule[day] = programWorkouts + extras
        }

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

        // If it's a new week, determine what to do
        if savedWeek != currentWeek {
            let programStore = ProgramStore.shared

            // If a program is active, try to advance to the next week
            if programStore.hasActiveProgram {
                let weekNumber = programStore.currentWeekNumber()
                if let weekNum = weekNumber,
                   let program = programStore.activeProgram,
                   weekNum >= 0,
                   weekNum < program.weeks.count {
                    // Advance the program week
                    userDefaults.set(currentWeek, forKey: weekIdentifierKey)
                    programStore.populateCurrentWeek()
                    tagProgramWorkouts(for: program.weeks[weekNum])
                    return
                } else {
                    // Program is complete or week out of range — deactivate
                    programStore.deactivate(completedAllWeeks: true)
                }
            }

            // No active program (or just deactivated) — clear as normal
            clearAllData()
            userDefaults.set(currentWeek, forKey: weekIdentifierKey)
            return
        }

        // Same week — load saved schedule
        guard let data = userDefaults.data(forKey: scheduleKey) else {
            // Fresh start for this week with an active program
            loadWeekFromActiveProgram()
            return
        }

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

            // Tag program workouts if a program is active
            tagProgramWorkoutsForCurrentWeek()
        } catch {
            ErrorReporter.shared.report("Failed to load schedule", source: "ScheduleStore.loadSchedule", error: error)
        }
    }

    private func loadWeekFromActiveProgram() {
        let programStore = ProgramStore.shared
        guard programStore.hasActiveProgram else { return }
        programStore.populateCurrentWeek()

        // Tag workouts after population
        if let weekNum = programStore.currentWeekNumber(),
           let program = programStore.activeProgram,
           weekNum >= 0,
           weekNum < program.weeks.count {
            tagProgramWorkouts(for: program.weeks[weekNum])
        }
    }

    private func tagProgramWorkoutsForCurrentWeek() {
        let programStore = ProgramStore.shared
        guard let weekNum = programStore.currentWeekNumber(),
              let program = programStore.activeProgram,
              weekNum >= 0,
              weekNum < program.weeks.count else { return }
        tagProgramWorkouts(for: program.weeks[weekNum])
    }

    private func tagProgramWorkouts(for week: ProgramWeek) {
        for day in week.days {
            programWorkoutIds[day.weekday] = Set(day.workoutIds)
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

        var emptyProgramIds: [Weekday: Set<UUID>] = [:]
        Weekday.allCases.forEach { emptyProgramIds[$0] = [] }
        programWorkoutIds = emptyProgramIds

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
