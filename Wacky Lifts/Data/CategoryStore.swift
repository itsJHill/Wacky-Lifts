import Foundation

final class CategoryStore {
    static let shared = CategoryStore()

    static let categoriesDidChangeNotification = Notification.Name("CategoryStore.categoriesDidChange")

    private let userDefaults = UserDefaults.standard
    private let categoriesKey = "workout_categories"

    private(set) var categories: [WorkoutCategory] {
        didSet {
            save()
            notifyChange()
        }
    }

    var sortedCategories: [WorkoutCategory] {
        categories.sorted { $0.order < $1.order }
    }

    private init() {
        if let data = userDefaults.data(forKey: categoriesKey),
           let saved = try? JSONDecoder().decode([WorkoutCategory].self, from: data) {
            categories = saved
        } else {
            // First launch - use defaults
            categories = WorkoutCategory.defaultCategories
            save()
        }
    }

    // MARK: - CRUD Operations

    func add(name: String) {
        let maxOrder = categories.map(\.order).max() ?? -1
        let category = WorkoutCategory(name: name, order: maxOrder + 1)
        categories.append(category)
    }

    func update(id: UUID, name: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
    }

    func delete(id: UUID) {
        ReferenceCleaner.onCategoryDeleted(id)
        categories.removeAll { $0.id == id }
        reindex()
    }

    func move(fromIndex: Int, toIndex: Int) {
        let sorted = sortedCategories
        guard fromIndex >= 0, fromIndex < sorted.count,
              toIndex >= 0, toIndex < sorted.count,
              fromIndex != toIndex else { return }

        var reordered = sorted
        let item = reordered.remove(at: fromIndex)
        reordered.insert(item, at: toIndex)

        // Update order values
        for (index, category) in reordered.enumerated() {
            if let catIndex = categories.firstIndex(where: { $0.id == category.id }) {
                categories[catIndex].order = index
            }
        }
    }

    func category(for id: UUID) -> WorkoutCategory? {
        categories.first { $0.id == id }
    }

    func category(named name: String) -> WorkoutCategory? {
        categories.first { $0.name == name }
    }

    // MARK: - Migration

    /// Migrates old enum-based category names to new category IDs
    func migrateCategory(fromName name: String) -> UUID? {
        // Try exact match first
        if let category = category(named: name) {
            return category.id
        }
        // Create a new category if it doesn't exist
        add(name: name)
        return category(named: name)?.id
    }

    // MARK: - Private

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            userDefaults.set(data, forKey: categoriesKey)
        }
    }

    private func reindex() {
        let sorted = sortedCategories
        for (index, category) in sorted.enumerated() {
            if let catIndex = categories.firstIndex(where: { $0.id == category.id }) {
                categories[catIndex].order = index
            }
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.categoriesDidChangeNotification, object: self)
    }

    func resetAll() {
        categories = WorkoutCategory.defaultCategories
    }

    /// Re-read categories from UserDefaults. The `categories` didSet triggers
    /// save + notify automatically. Called by `DataBackupManager` after import.
    func reloadFromDisk() {
        if let data = userDefaults.data(forKey: categoriesKey),
           let saved = try? JSONDecoder().decode([WorkoutCategory].self, from: data) {
            categories = saved
        } else {
            categories = WorkoutCategory.defaultCategories
        }
    }
}
