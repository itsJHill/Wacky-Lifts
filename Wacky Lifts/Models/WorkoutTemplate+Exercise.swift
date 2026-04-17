import Foundation

// MARK: - Nested Exercise entry

/// A single exercise entry inside a `WorkoutTemplate`. Has its own per-workout
/// `id` (so completion/log keys survive renames) plus an `exerciseId` that
/// foreign-keys into `ExerciseStore`'s shared exercise library. Name and
/// machine are resolved through the library so edits propagate everywhere.
extension WorkoutTemplate {
    struct Exercise: Identifiable, Hashable, Codable, Sendable {
        /// Unique per workout entry — preserves completion/log keys
        let id: UUID
        /// FK to the exercise library (ExerciseDefinition.id) — shared across workouts
        let exerciseId: UUID
        let sets: String
        let reps: String
        let defaultWeight: Double?
        let duration: String?

        private enum CodingKeys: String, CodingKey {
            case id, exerciseId, name, sets, reps, defaultWeight, duration, machineId
        }

        init(
            id: UUID = UUID(),
            exerciseId: UUID,
            sets: String,
            reps: String,
            defaultWeight: Double? = nil,
            duration: String? = nil
        ) {
            self.id = id
            self.exerciseId = exerciseId
            self.sets = sets
            self.reps = reps
            self.defaultWeight = defaultWeight
            self.duration = duration
        }

        /// Legacy convenience init for default templates — looks up or creates an exercise in the library.
        init(
            id: UUID = UUID(),
            name: String,
            sets: String,
            reps: String,
            defaultWeight: Double? = nil,
            duration: String? = nil,
            machineId: UUID? = nil
        ) {
            self.id = id
            self.exerciseId = Self.resolveOrCreateExercise(name: name, machineId: machineId)
            self.sets = sets
            self.reps = reps
            self.defaultWeight = defaultWeight
            self.duration = duration
        }

        /// Finds an existing library exercise by name, or creates one.
        /// Delegates to the store's atomic `findOrCreate` so the lookup and insert
        /// can't be split across callers and produce duplicates.
        private static func resolveOrCreateExercise(name: String, machineId: UUID?) -> UUID {
            ExerciseStore.shared.findOrCreate(name: name, machineId: machineId).id
        }

        // Custom decoding to handle migration from old format (inline name/machineId)
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            sets = try container.decode(String.self, forKey: .sets)
            reps = try container.decode(String.self, forKey: .reps)
            defaultWeight = try container.decodeIfPresent(Double.self, forKey: .defaultWeight)
            duration = try container.decodeIfPresent(String.self, forKey: .duration)

            // New format has exerciseId; old format has inline name/machineId
            if let eid = try container.decodeIfPresent(UUID.self, forKey: .exerciseId) {
                exerciseId = eid
            } else {
                // Legacy: read inline name and machineId, resolve to library exercise
                let legacyName = try container.decode(String.self, forKey: .name)
                let legacyMachineId = try container.decodeIfPresent(UUID.self, forKey: .machineId)
                exerciseId = Self.resolveOrCreateExercise(name: legacyName, machineId: legacyMachineId)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(exerciseId, forKey: .exerciseId)
            try container.encode(sets, forKey: .sets)
            try container.encode(reps, forKey: .reps)
            try container.encodeIfPresent(defaultWeight, forKey: .defaultWeight)
            try container.encodeIfPresent(duration, forKey: .duration)
        }

        // MARK: - Computed properties resolved from exercise library

        var name: String {
            ExerciseStore.shared.exercise(for: exerciseId)?.name ?? ""
        }

        var machineId: UUID? {
            ExerciseStore.shared.exercise(for: exerciseId)?.machineId
        }

        func withDefaultWeight(_ weight: Double?) -> Exercise {
            Exercise(
                id: id,
                exerciseId: exerciseId,
                sets: sets,
                reps: reps,
                defaultWeight: weight,
                duration: duration
            )
        }

        /// Parses the duration string (e.g., "5 min", "30 sec") into seconds
        var durationInSeconds: TimeInterval? {
            guard let duration = duration, !duration.isEmpty else { return nil }
            let lowered = duration.lowercased()
            let scanner = Scanner(string: lowered)
            guard let value = scanner.scanDouble() else { return nil }
            let remaining = lowered[scanner.currentIndex...].trimmingCharacters(in: .whitespaces)
            if remaining.hasPrefix("sec") || remaining.hasPrefix("s") { return value }
            if remaining.hasPrefix("hr") || remaining.hasPrefix("h") { return value * 3600 }
            return value * 60 // default to minutes
        }

        /// Parses the sets string into an integer count (returns 1 if empty or unparseable)
        var parsedSetCount: Int {
            guard !sets.isEmpty else { return 1 }
            let scanner = Scanner(string: sets)
            scanner.charactersToBeSkipped = CharacterSet.decimalDigits.inverted
            var value: Int = 0
            return scanner.scanInt(&value) && value > 0 ? value : 1
        }

        /// Whether this exercise is primarily duration-based with no meaningful sets for weight tracking
        var isDurationOnly: Bool {
            let hasDuration = duration != nil && !duration!.isEmpty
            return hasDuration && sets.isEmpty
        }

        /// Human-readable summary of sets/reps/duration
        var detailSummary: String {
            let hasSets = !sets.isEmpty
            let hasReps = !reps.isEmpty
            let hasDuration = duration != nil && !duration!.isEmpty

            if hasSets && hasReps && hasDuration {
                return "\(sets) sets (\(reps) reps) • \(duration!)"
            } else if hasDuration && hasSets && !hasReps {
                return "\(sets) sets • \(duration!)"
            } else if hasDuration && !hasSets {
                return duration!
            } else {
                let setsText = hasSets ? "\(sets) sets" : ""
                let repsText = hasReps ? "(\(reps) reps)" : ""
                return [setsText, repsText].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
    }
}
