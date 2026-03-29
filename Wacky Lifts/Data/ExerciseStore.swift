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

    /// When true, `add` skips saving/notifying — used during migration to batch inserts.
    private var isBatching = false

    /// Perform multiple additions without saving/notifying after each one.
    /// Saves once and notifies once when the block completes.
    func performBatchUpdates(_ block: () -> Void) {
        isBatching = true
        block()
        isBatching = false
        save()
        notifyChange()
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

    // MARK: - Persistence

    private func loadExercises() {
        guard let data = userDefaults.data(forKey: exercisesKey),
              let decoded = try? decoder.decode([Exercise].self, from: data) else {
            exercises = []
            return
        }
        exercises = decoded
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
