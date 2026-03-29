import Foundation

final class ScheduleStore {
    static let shared = ScheduleStore()

    static let scheduleDidChangeNotification = Notification.Name("ScheduleStore.scheduleDidChange")

    private let userDefaults = UserDefaults.standard
    private let scheduleKey = "weekly_schedule"
    private let weekIdentifierKey = "schedule_week_identifier"

    private(set) var schedule: [Weekday: [WorkoutTemplate]] = {
        var map: [Weekday: [WorkoutTemplate]] = [:]
        Weekday.allCases.forEach { map[$0] = [] }
        return map
    }()

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
    func refreshFromLibrary() {
        let library = WorkoutLibraryStore.shared
        var updated: [Weekday: [WorkoutTemplate]] = [:]
        Weekday.allCases.forEach { day in
            let existing = schedule[day] ?? []
            let mapped = existing.compactMap { library.template(withId: $0.id) }
            updated[day] = mapped
        }
        schedule = updated
        save()
        notifyChange()
    }

    // MARK: - Persistence

    private func currentWeekIdentifier() -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 1 // Sunday
        let today = Date()
        let year = calendar.component(.yearForWeekOfYear, from: today)
        let week = calendar.component(.weekOfYear, from: today)
        return "\(year)-W\(week)"
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
            Weekday.allCases.forEach { loadedSchedule[$0] = [] }

            for (weekdayRaw, workoutIds) in savedSchedule.weekdayWorkouts {
                guard let weekday = Weekday(rawValue: weekdayRaw) else { continue }
                let workouts = workoutIds.compactMap { library.template(withId: $0) }
                loadedSchedule[weekday] = workouts
            }

            schedule = loadedSchedule
        } catch {
            print("Failed to load schedule: \(error)")
        }
    }

    private func save() {
        let currentWeek = currentWeekIdentifier()
        userDefaults.set(currentWeek, forKey: weekIdentifierKey)

        var weekdayWorkouts: [Int: [UUID]] = [:]
        for (weekday, workouts) in schedule {
            weekdayWorkouts[weekday.rawValue] = workouts.map { $0.id }
        }

        let savedSchedule = SavedSchedule(weekdayWorkouts: weekdayWorkouts)

        do {
            let data = try JSONEncoder().encode(savedSchedule)
            userDefaults.set(data, forKey: scheduleKey)
        } catch {
            print("Failed to save schedule: \(error)")
        }
    }

    private func clearAllData() {
        var emptySchedule: [Weekday: [WorkoutTemplate]] = [:]
        Weekday.allCases.forEach { emptySchedule[$0] = [] }
        schedule = emptySchedule
        userDefaults.removeObject(forKey: scheduleKey)
    }

    func resetAll() {
        clearAllData()
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
