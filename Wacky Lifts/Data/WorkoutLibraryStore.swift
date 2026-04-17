import Foundation

final class WorkoutLibraryStore {
    static let shared = WorkoutLibraryStore()

    static let libraryDidChangeNotification =
        Notification.Name("WorkoutLibraryStore.libraryDidChange")

    private let userDefaults = UserDefaults.standard
    private let libraryKey = "workout_library"
    private let hasInitializedKey = "workout_library_initialized"

    private(set) var templates: [WorkoutTemplate]

    private init() {
        if let data = userDefaults.data(forKey: libraryKey),
           let saved = try? JSONDecoder().decode([WorkoutTemplate].self, from: data) {
            templates = saved
        } else {
            // First launch - save defaults with stable IDs
            templates = WorkoutLibrary.templates
            save()
            userDefaults.set(true, forKey: hasInitializedKey)
        }
    }

    var categoryIds: [UUID] {
        CategoryStore.shared.sortedCategories.map(\.id)
    }

    var categorized: [UUID: [WorkoutTemplate]] {
        Dictionary(grouping: templates, by: { $0.categoryId })
    }

    func template(withId id: WorkoutTemplate.ID) -> WorkoutTemplate? {
        templates.first { $0.id == id }
    }

    func add(_ template: WorkoutTemplate) {
        templates.append(template)
        save()
        notifyChange()
    }

    func update(_ template: WorkoutTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        save()
        notifyChange()
    }

    func delete(id: WorkoutTemplate.ID) {
        ReferenceCleaner.onWorkoutDeleted(id)
        templates.removeAll { $0.id == id }
        save()
        notifyChange()
    }

    func replaceAll(with templates: [WorkoutTemplate]) {
        self.templates = templates
        save()
        notifyChange()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(templates) {
            userDefaults.set(data, forKey: libraryKey)
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: self)
    }

    func resetAll() {
        templates = WorkoutLibrary.templates
        save()
        notifyChange()
    }

    /// Re-read templates from UserDefaults and notify observers. Called by
    /// `DataBackupManager` after an import so running view controllers pick
    /// up the restored data without the app needing to relaunch.
    func reloadFromDisk() {
        if let data = userDefaults.data(forKey: libraryKey),
           let saved = try? JSONDecoder().decode([WorkoutTemplate].self, from: data) {
            templates = saved
        } else {
            templates = WorkoutLibrary.templates
        }
        notifyChange()
    }
}
