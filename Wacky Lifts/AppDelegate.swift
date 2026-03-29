import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        migrateToExerciseLibraryIfNeeded()
        return true
    }

    /// One-time migration: extract exercises from workout templates into the exercise library,
    /// then rewrite WeightLogStore PRs to use shared library exercise IDs.
    private func migrateToExerciseLibraryIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "exercise_library_migrated"
        guard !defaults.bool(forKey: migrationKey) else { return }

        // 1. Touch ExerciseStore so it's initialized (empty on first migration)
        let exerciseStore = ExerciseStore.shared

        // 2. Load WorkoutLibraryStore — the decoder auto-populates ExerciseStore
        //    via resolveOrCreateExercise for any legacy exercises without exerciseId.
        //    Batch so we only save/notify once after all exercises are created.
        var store: WorkoutLibraryStore!
        exerciseStore.performBatchUpdates {
            store = WorkoutLibraryStore.shared
        }

        // 3. Build old-entry-ID → library-exercise-ID mapping from migrated templates
        var mapping: [UUID: UUID] = [:]
        for template in store.templates {
            for exercise in template.exercises {
                // exercise.id is the entry ID, exercise.exerciseId is the library ID
                mapping[exercise.id] = exercise.exerciseId
            }
        }

        // 4. Migrate WeightLogStore (rewrites exerciseId in logs, merges PRs)
        if !mapping.isEmpty {
            WeightLogStore.shared.migrateToExerciseLibrary(mapping: mapping)
        }

        // 5. Re-save templates so they persist in the new format with exerciseId
        store.replaceAll(with: store.templates)

        defaults.set(true, forKey: migrationKey)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {}

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}
