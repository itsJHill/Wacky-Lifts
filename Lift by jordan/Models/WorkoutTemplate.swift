import Foundation

/// Typealias to disambiguate from WorkoutTemplate.Exercise
typealias ExerciseDefinition = Exercise

struct WorkoutTemplate: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let categoryId: UUID
    let exercises: [Exercise]
    let iconName: String?

    init(
        id: UUID = UUID(),
        name: String,
        categoryId: UUID,
        exercises: [Exercise],
        iconName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.categoryId = categoryId
        self.exercises = exercises
        self.iconName = iconName
    }

    // Convenience computed property to get the category name
    var categoryName: String {
        CategoryStore.shared.category(for: categoryId)?.name ?? "Uncategorized"
    }

    // Custom decoding to handle migration from old enum format
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        exercises = try container.decode([Exercise].self, forKey: .exercises)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)

        // Try to decode as UUID first (new format)
        if let uuid = try? container.decode(UUID.self, forKey: .categoryId) {
            categoryId = uuid
        } else if let legacyCategory = try? container.decode(LegacyCategory.self, forKey: .category) {
            // Migrate from old enum format
            categoryId = CategoryStore.shared.migrateCategory(fromName: legacyCategory.rawValue) ?? UUID()
        } else {
            // Fallback - try to get first category
            categoryId = CategoryStore.shared.sortedCategories.first?.id ?? UUID()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, categoryId, category, exercises, iconName
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(exercises, forKey: .exercises)
        try container.encodeIfPresent(iconName, forKey: .iconName)
    }

    /// Whether every exercise in this workout has a duration component
    var isAllDuration: Bool {
        !exercises.isEmpty && exercises.allSatisfy { $0.duration != nil && !$0.duration!.isEmpty }
    }

    // Legacy enum for migration
    private enum LegacyCategory: String, Codable {
        case classic3Day = "Classic 3-Day"
        case pushPullLegs = "Push / Pull / Legs"
        case upperLower = "Upper / Lower"
        case upperLowerUpper = "Upper / Lower / Upper"
        case fullBody = "Full Body"
        case upperLowerFull = "Upper / Lower / Full Body"
    }
}
