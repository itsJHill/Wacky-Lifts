import Foundation

/// Represents a logged weight/rep entry for an exercise
struct ExerciseLog: Codable, Identifiable, Hashable {
    let id: UUID
    /// Per-workout-entry ID (WorkoutTemplate.Exercise.id) — unique per workout entry.
    /// Used for composite log keys so logs remain workout-specific.
    let entryId: UUID
    /// Library exercise ID (Exercise.id) — shared across workouts.
    /// Used for PR tracking so PRs unify across workouts.
    let exerciseId: UUID
    let exerciseName: String
    let workoutId: UUID
    let date: Date
    let weight: Double
    let reps: Int
    let unit: WeightUnit
    let isPersonalRecord: Bool
    let setWeights: [Double]?

    private enum CodingKeys: String, CodingKey {
        case id, entryId, exerciseId, exerciseName, workoutId, date, weight, reps, unit, isPersonalRecord, setWeights
    }

    init(
        id: UUID = UUID(),
        entryId: UUID,
        exerciseId: UUID,
        exerciseName: String,
        workoutId: UUID,
        date: Date,
        weight: Double,
        reps: Int,
        unit: WeightUnit,
        isPersonalRecord: Bool = false,
        setWeights: [Double]? = nil
    ) {
        self.id = id
        self.entryId = entryId
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.workoutId = workoutId
        self.date = date
        self.weight = weight
        self.reps = reps
        self.unit = unit
        self.isPersonalRecord = isPersonalRecord
        self.setWeights = setWeights
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseId = try container.decode(UUID.self, forKey: .exerciseId)
        // Migration: old logs don't have entryId — default to exerciseId (which was the entry ID in old format)
        entryId = try container.decodeIfPresent(UUID.self, forKey: .entryId) ?? exerciseId
        exerciseName = try container.decode(String.self, forKey: .exerciseName)
        workoutId = try container.decode(UUID.self, forKey: .workoutId)
        date = try container.decode(Date.self, forKey: .date)
        weight = try container.decode(Double.self, forKey: .weight)
        reps = try container.decode(Int.self, forKey: .reps)
        unit = try container.decode(WeightUnit.self, forKey: .unit)
        isPersonalRecord = try container.decode(Bool.self, forKey: .isPersonalRecord)
        setWeights = try container.decodeIfPresent([Double].self, forKey: .setWeights)
    }

    /// Create a copy with updated PR status
    func withPersonalRecord(_ isPR: Bool) -> ExerciseLog {
        ExerciseLog(
            id: id,
            entryId: entryId,
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            workoutId: workoutId,
            date: date,
            weight: weight,
            reps: reps,
            unit: unit,
            isPersonalRecord: isPR,
            setWeights: setWeights
        )
    }
}

/// Weight unit preference
enum WeightUnit: String, Codable, CaseIterable {
    case lbs
    case kg

    var symbol: String {
        rawValue
    }

    var increment: Double {
        switch self {
        case .lbs: return 5.0
        case .kg: return 2.5
        }
    }
}
