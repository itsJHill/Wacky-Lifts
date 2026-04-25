import Foundation

final class CompletionStore {
    static let shared = CompletionStore()

    static let completionsDidChangeNotification = Notification.Name("CompletionStore.completionsDidChange")

    private let userDefaults = UserDefaults.standard
    private let completionsKey = "exercise_completions"
    private var completions: Set<String> {
        didSet {
            save()
        }
    }

    private init() {
        if let stored = userDefaults.stringArray(forKey: completionsKey) {
            completions = Set(stored)
        } else {
            completions = []
        }
    }

    private static let dateFormatter: DateFormatter = {
        AppDateCoding.makeDateKeyFormatter()
    }()

    private struct CompletionKeyParts {
        let date: Date
        let dateString: String
        let workoutId: UUID
        let exerciseId: UUID
    }

    private func parseKey(_ key: String) -> CompletionKeyParts? {
        let components = key.split(separator: "_")
        guard components.count == 3,
              let date = Self.dateFormatter.date(from: String(components[0])),
              let workoutId = UUID(uuidString: String(components[1])),
              let exerciseId = UUID(uuidString: String(components[2])) else { return nil }

        return CompletionKeyParts(
            date: date,
            dateString: String(components[0]),
            workoutId: workoutId,
            exerciseId: exerciseId
        )
    }

    private func key(for exerciseId: UUID, in workoutId: UUID, on date: Date) -> String {
        let dateString = Self.dateFormatter.string(from: date)
        return "\(dateString)_\(workoutId.uuidString)_\(exerciseId.uuidString)"
    }

    func isExerciseCompleted(exerciseId: UUID, in workoutId: UUID, on date: Date) -> Bool {
        completions.contains(key(for: exerciseId, in: workoutId, on: date))
    }

    func setExerciseCompleted(_ completed: Bool, exerciseId: UUID, in workoutId: UUID, on date: Date) {
        let k = key(for: exerciseId, in: workoutId, on: date)
        let wasCompleted = completions.contains(k)
        if completed && !wasCompleted {
            completions.insert(k)
            StreakStore.shared.recordExerciseCompletion(on: date)
        } else if !completed && wasCompleted {
            completions.remove(k)
            let dateString = Self.dateFormatter.string(from: date)
            let remainingOnDate = completions.contains { $0.hasPrefix(dateString) }
            StreakStore.shared.removeExerciseCompletions(1, on: date, removeActivityDate: !remainingOnDate)
        }
        notifyChange()
    }

    func toggleExerciseCompletion(exerciseId: UUID, in workoutId: UUID, on date: Date) {
        let k = key(for: exerciseId, in: workoutId, on: date)
        if completions.contains(k) {
            completions.remove(k)
            let dateString = Self.dateFormatter.string(from: date)
            let remainingOnDate = completions.contains { $0.hasPrefix(dateString) }
            StreakStore.shared.removeExerciseCompletions(1, on: date, removeActivityDate: !remainingOnDate)
        } else {
            completions.insert(k)
            StreakStore.shared.recordExerciseCompletion(on: date)
        }
        notifyChange()
    }

    func checkAndRecordWorkoutCompletion(for workout: WorkoutTemplate, on date: Date, wasFullyCompleted: Bool) {
        let isNowFullyCompleted = isWorkoutFullyCompleted(workout, on: date)
        if !wasFullyCompleted && isNowFullyCompleted {
            StreakStore.shared.recordWorkoutCompletion(on: date)
        } else if wasFullyCompleted && !isNowFullyCompleted {
            let hasRemainingFullWorkout = hasFullWorkoutCompletionOnDate(date, excludingWorkout: workout.id)
            StreakStore.shared.recordWorkoutUncompletion(on: date, removeWorkoutDate: !hasRemainingFullWorkout)
        }
    }

    func completedExerciseCount(for workout: WorkoutTemplate, on date: Date) -> Int {
        workout.exercises.filter { isExerciseCompleted(exerciseId: $0.id, in: workout.id, on: date) }.count
    }

    func isWorkoutFullyCompleted(_ workout: WorkoutTemplate, on date: Date) -> Bool {
        guard !workout.exercises.isEmpty else { return false }
        return completedExerciseCount(for: workout, on: date) == workout.exercises.count
    }

    /// Clears completion data for specific exercises within a workout (e.g. when exercises are removed from a template)
    func clearCompletions(forExerciseIds exerciseIds: Set<UUID>, in workoutId: UUID) {
        guard !exerciseIds.isEmpty else { return }

        let oldCompletions = completions
        var newCompletions = Set<String>()
        var removedByDate: [String: Int] = [:]

        for key in oldCompletions {
            guard let parts = parseKey(key) else {
                newCompletions.insert(key)
                continue
            }

            if parts.workoutId == workoutId && exerciseIds.contains(parts.exerciseId) {
                removedByDate[parts.dateString, default: 0] += 1
            } else {
                newCompletions.insert(key)
            }
        }

        guard !removedByDate.isEmpty else { return }
        completions = newCompletions

        let streakStore = StreakStore.shared

        for (dateString, count) in removedByDate {
            guard let date = Self.dateFormatter.date(from: dateString) else { continue }
            let remainingOnDate = newCompletions.contains { $0.hasPrefix(dateString) }
            streakStore.removeExerciseCompletions(count, on: date, removeActivityDate: !remainingOnDate)
        }

        notifyChange()
    }

    /// Clears all completion data for a workout
    func clearCompletions(for workoutId: UUID) {
        let workoutIdString = workoutId.uuidString
        let oldCompletions = completions
        var newCompletions = Set<String>()
        var removedByDate: [String: [CompletionKeyParts]] = [:]
        var newCountsByDate: [String: Int] = [:]
        var newCountsByDateWorkout: [String: [UUID: Int]] = [:]

        for key in oldCompletions {
            guard let parts = parseKey(key) else {
                newCompletions.insert(key)
                continue
            }

            if parts.workoutId.uuidString == workoutIdString {
                removedByDate[parts.dateString, default: []].append(parts)
            } else {
                newCompletions.insert(key)
                newCountsByDate[parts.dateString, default: 0] += 1
                var workoutCounts = newCountsByDateWorkout[parts.dateString, default: [:]]
                workoutCounts[parts.workoutId, default: 0] += 1
                newCountsByDateWorkout[parts.dateString] = workoutCounts
            }
        }

        guard !removedByDate.isEmpty else { return }
        completions = newCompletions

        let snapshotStore = WorkoutSnapshotStore.shared
        let libraryStore = WorkoutLibraryStore.shared
        let streakStore = StreakStore.shared

        for (dateString, removedParts) in removedByDate {
            guard let date = Self.dateFormatter.date(from: dateString) else { continue }
            let removedExerciseCount = removedParts.count
            let remainingExerciseCount = newCountsByDate[dateString] ?? 0
            let removeActivityDate = remainingExerciseCount == 0

            streakStore.removeExerciseCompletions(
                removedExerciseCount,
                on: date,
                removeActivityDate: removeActivityDate
            )

            if let workout = snapshotStore.snapshot(for: workoutId, on: date)
                ?? libraryStore.template(withId: workoutId) {
                let exerciseCount = workout.exercises.count
                if exerciseCount > 0 && removedExerciseCount >= exerciseCount {
                    let hasRemainingFullWorkout = hasFullWorkoutCompletion(
                        on: date,
                        countsByWorkout: newCountsByDateWorkout[dateString] ?? [:],
                        snapshotStore: snapshotStore,
                        libraryStore: libraryStore
                    )
                    streakStore.removeWorkoutCompletion(
                        on: date,
                        removeWorkoutDate: !hasRemainingFullWorkout
                    )
                } else if removeActivityDate {
                    streakStore.removeWorkoutDate(on: date)
                }
            } else if removeActivityDate {
                streakStore.removeWorkoutDate(on: date)
            }
        }

        notifyChange()
    }

    /// Clears completion data for a specific workout on a specific date
    func clearCompletions(for workoutId: UUID, on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        let prefix = "\(dateString)_\(workoutId.uuidString)_"
        let removedParts = completions.compactMap(parseKey).filter { $0.dateString == dateString && $0.workoutId == workoutId }
        guard !removedParts.isEmpty else { return }

        completions = completions.filter { !$0.hasPrefix(prefix) }

        let snapshotStore = WorkoutSnapshotStore.shared
        let libraryStore = WorkoutLibraryStore.shared
        let streakStore = StreakStore.shared

        let removedExerciseCount = removedParts.count
        let remainingOnDate = completions.contains { $0.hasPrefix(dateString) }
        streakStore.removeExerciseCompletions(removedExerciseCount, on: date, removeActivityDate: !remainingOnDate)

        if let workout = snapshotStore.snapshot(for: workoutId, on: date)
            ?? libraryStore.template(withId: workoutId) {
            let exerciseCount = workout.exercises.count
            if exerciseCount > 0 && removedExerciseCount >= exerciseCount {
                let hasRemainingFullWorkout = hasFullWorkoutCompletionOnDate(date, excludingWorkout: workoutId)
                streakStore.removeWorkoutCompletion(on: date, removeWorkoutDate: !hasRemainingFullWorkout)
            }
        }

        if !remainingOnDate {
            streakStore.removeWorkoutDate(on: date)
        }

        notifyChange()
    }

    private func hasFullWorkoutCompletionOnDate(_ date: Date, excludingWorkout: UUID) -> Bool {
        let dateString = Self.dateFormatter.string(from: date)
        var countsByWorkout: [UUID: Int] = [:]
        for key in completions {
            guard key.hasPrefix(dateString), let parts = parseKey(key), parts.workoutId != excludingWorkout else { continue }
            countsByWorkout[parts.workoutId, default: 0] += 1
        }
        let snapshotStore = WorkoutSnapshotStore.shared
        let libraryStore = WorkoutLibraryStore.shared
        return hasFullWorkoutCompletion(on: date, countsByWorkout: countsByWorkout, snapshotStore: snapshotStore, libraryStore: libraryStore)
    }

    func clearCompletions(on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        let removedParts = completions.compactMap(parseKey).filter { $0.dateString == dateString }
        guard !removedParts.isEmpty else { return }

        completions = completions.filter { !$0.hasPrefix(dateString) }

        let snapshotStore = WorkoutSnapshotStore.shared
        let libraryStore = WorkoutLibraryStore.shared
        let streakStore = StreakStore.shared

        let removedExerciseCount = removedParts.count
        streakStore.removeExerciseCompletions(removedExerciseCount, on: date, removeActivityDate: true)

        var workoutCounts: [UUID: Int] = [:]
        for part in removedParts {
            workoutCounts[part.workoutId, default: 0] += 1
        }

        var fullWorkoutCount = 0
        for (workoutId, completedCount) in workoutCounts {
            guard let workout = snapshotStore.snapshot(for: workoutId, on: date)
                ?? libraryStore.template(withId: workoutId) else { continue }
            let exerciseCount = workout.exercises.count
            if exerciseCount > 0 && completedCount >= exerciseCount {
                fullWorkoutCount += 1
            }
        }

        if fullWorkoutCount > 0 {
            for _ in 0..<fullWorkoutCount {
                streakStore.removeWorkoutCompletion(on: date, removeWorkoutDate: false)
            }
        }

        streakStore.removeWorkoutDate(on: date)
        notifyChange()
    }

    private func hasFullWorkoutCompletion(
        on date: Date,
        countsByWorkout: [UUID: Int],
        snapshotStore: WorkoutSnapshotStore,
        libraryStore: WorkoutLibraryStore
    ) -> Bool {
        for (workoutId, completedCount) in countsByWorkout {
            guard let workout = snapshotStore.snapshot(for: workoutId, on: date)
                ?? libraryStore.template(withId: workoutId) else { continue }
            let exerciseCount = workout.exercises.count
            if exerciseCount > 0 && completedCount >= exerciseCount {
                return true
            }
        }
        return false
    }

    private func save() {
        userDefaults.set(Array(completions), forKey: completionsKey)
    }

    func resetAll() {
        completions = []
        notifyChange()
    }

    /// Re-read completions from UserDefaults. Called by `DataBackupManager`
    /// after import.
    func reloadFromDisk() {
        if let stored = userDefaults.stringArray(forKey: completionsKey) {
            completions = Set(stored)
        } else {
            completions = []
        }
        notifyChange()
    }

    /// Get workout IDs that had completions on a specific date
    func workoutIdsWithCompletions(on date: Date) -> Set<UUID> {
        let dateString = Self.dateFormatter.string(from: date)
        var workoutIds = Set<UUID>()

        for key in completions {
            // Key format: "yyyy-MM-dd_workoutId_exerciseId"
            guard key.hasPrefix(dateString) else { continue }
            let components = key.split(separator: "_")
            guard components.count >= 2 else { continue }
            if let workoutId = UUID(uuidString: String(components[1])) {
                workoutIds.insert(workoutId)
            }
        }

        return workoutIds
    }

    /// Get count of completed exercises for a workout on a specific date
    func completedExerciseCount(for workoutId: UUID, on date: Date) -> Int {
        let dateString = Self.dateFormatter.string(from: date)
        let prefix = "\(dateString)_\(workoutId.uuidString)_"

        return completions.filter { $0.hasPrefix(prefix) }.count
    }

    var totalCompletedExercises: Int {
        completions.count
    }

    var completedExercisesThisYear: Int {
        let yearPrefix = String(Self.dateFormatter.string(from: Date()).prefix(4))
        return completions.filter { $0.hasPrefix(yearPrefix) }.count
    }

    var completedExercisesThisMonth: Int {
        let prefix = Self.dateFormatter.string(from: Date()).prefix(7) // "yyyy-MM"
        return completions.filter { $0.hasPrefix(prefix) }.count
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.completionsDidChangeNotification, object: self)
    }

}
