import Foundation

final class ExerciseStore {
    static let shared = ExerciseStore()

    static let exercisesDidChangeNotification =
        Notification.Name("ExerciseStore.exercisesDidChange")

    private let userDefaults = UserDefaults.standard
    private let exercisesKey = "exercise_library"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var exercises: [Exercise] = [] {
        didSet {
            rebuildCache()
        }
    }

    /// Fast UUID → Exercise lookup
    private var cache: [UUID: Exercise] = [:]

    private init() {
        loadExercises()
    }

    // MARK: - Lookup

    func exercise(for id: UUID) -> Exercise? {
        cache[id]
    }

    func sortedByName() -> [Exercise] {
        exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Returns all workouts that reference the given exercise ID
    func workoutsUsing(exerciseId: UUID) -> [WorkoutTemplate] {
        WorkoutLibraryStore.shared.templates.filter { template in
            template.exercises.contains { $0.exerciseId == exerciseId }
        }
    }

    /// Depth counter so nested `performBatchUpdates` calls don't prematurely end batching.
    private var batchDepth = 0
    private var isBatching: Bool { batchDepth > 0 }

    /// Perform multiple additions without saving/notifying after each one.
    /// Saves once and notifies once when the outermost block completes.
    func performBatchUpdates(_ block: () -> Void) {
        batchDepth += 1
        block()
        batchDepth -= 1
        if batchDepth == 0 {
            save()
            notifyChange()
        }
    }

    // MARK: - CRUD

    func add(_ exercise: Exercise) {
        exercises.append(exercise)
        if !isBatching {
            save()
            notifyChange()
        }
    }

    func update(_ exercise: Exercise) {
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        exercises[index] = exercise
        save()
        notifyChange()
    }

    func delete(id: UUID) {
        ReferenceCleaner.onExerciseDeleted(id)
        exercises.removeAll { $0.id == id }
        save()
        notifyChange()
    }

    func replaceAll(with newExercises: [Exercise]) {
        exercises = newExercises
        save()
        notifyChange()
    }

    func resetAll() {
        exercises = []
        save()
        notifyChange()
    }

    /// Finds an existing library exercise with the given name (case-insensitive),
    /// or creates and persists a new one. Consolidates the find-then-add pattern
    /// so callers (notably the legacy decoder path) can't accidentally introduce
    /// duplicates by checking and inserting in separate steps.
    func findOrCreate(name: String, machineId: UUID?) -> Exercise {
        if let existing = exercises.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }
        let newExercise = Exercise(name: name, machineId: machineId)
        add(newExercise)
        return newExercise
    }

    // MARK: - Persistence

    private func loadExercises() {
        guard let data = userDefaults.data(forKey: exercisesKey),
              let decoded = try? decoder.decode([Exercise].self, from: data) else {
            exercises = []
            return
        }
        exercises = decoded
    }

    /// Re-read exercises from UserDefaults and notify observers. Called by
    /// `DataBackupManager` after an import.
    func reloadFromDisk() {
        loadExercises()
        notifyChange()
    }

    private func save() {
        guard let data = try? encoder.encode(exercises) else { return }
        userDefaults.set(data, forKey: exercisesKey)
    }

    private func rebuildCache() {
        var newCache: [UUID: Exercise] = [:]
        for exercise in exercises {
            newCache[exercise.id] = exercise
        }
        cache = newCache
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.exercisesDidChangeNotification, object: self)
    }
}
