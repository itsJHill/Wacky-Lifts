import Foundation

/// A standalone exercise entity in the exercise library.
/// Workouts reference exercises by `id` rather than embedding exercise definitions inline.
struct Exercise: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var machineId: UUID?

    init(id: UUID = UUID(), name: String, machineId: UUID? = nil) {
        self.id = id
        self.name = name
        self.machineId = machineId
    }
}
