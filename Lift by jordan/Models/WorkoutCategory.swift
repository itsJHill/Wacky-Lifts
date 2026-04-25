import Foundation

struct WorkoutCategory: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var order: Int

    init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}

extension WorkoutCategory {
    static let defaultCategories: [WorkoutCategory] = [
        WorkoutCategory(name: "Push / Pull / Legs", order: 0),
        WorkoutCategory(name: "Upper / Lower", order: 1),
        WorkoutCategory(name: "Full Body", order: 2),
        WorkoutCategory(name: "Classic 3-Day", order: 3),
        WorkoutCategory(name: "Upper / Lower / Upper", order: 4),
        WorkoutCategory(name: "Upper / Lower / Full Body", order: 5),
        WorkoutCategory(name: "Cardio", order: 6),
    ]
}
