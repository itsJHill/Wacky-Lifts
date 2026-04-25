import Foundation

/// Handles referential-integrity cleanup when an entity is deleted.
/// Centralizes cross-store cascade logic so individual stores don't have
/// to reach into each other's internals, and so the behavior of "delete X"
/// is identical no matter which screen triggers it.
///
/// Convention: call the relevant hook *before* the source store removes the
/// entity. Some cleanup steps rely on looking the entity up, and callers
/// further downstream (e.g. `CompletionStore.clearCompletions(for:)`) consult
/// `WorkoutLibraryStore` to compute remaining exercise counts.
enum ReferenceCleaner {

    /// Called before a library exercise is deleted. Strips any workout-template
    /// entry referencing the exercise. Historical weight logs and completion
    /// records are preserved intentionally — users shouldn't lose streak/PR
    /// history just because they renamed/removed the underlying exercise.
    static func onExerciseDeleted(_ exerciseId: UUID) {
        let library = WorkoutLibraryStore.shared
        var updated: [WorkoutTemplate] = []
        var changed = false
        for template in library.templates {
            let filtered = template.exercises.filter { $0.exerciseId != exerciseId }
            if filtered.count != template.exercises.count {
                changed = true
                updated.append(
                    WorkoutTemplate(
                        id: template.id,
                        name: template.name,
                        categoryId: template.categoryId,
                        exercises: filtered,
                        iconName: template.iconName
                    )
                )
            } else {
                updated.append(template)
            }
        }
        if changed {
            library.replaceAll(with: updated)
        }
    }

    /// Called before a workout template is deleted. Purges everything else
    /// that referenced the workout id: schedule entries, weight logs / PRs,
    /// completion records, and captured template snapshots.
    static func onWorkoutDeleted(_ workoutId: UUID) {
        let schedule = ScheduleStore.shared
        for day in Weekday.allCases {
            schedule.remove(templateId: workoutId, from: day)
        }
        WeightLogStore.shared.deleteLogsAndRecalculatePRs(for: workoutId)
        CompletionStore.shared.clearCompletions(for: workoutId)
        WorkoutSnapshotStore.shared.deleteSnapshots(for: workoutId)
    }

    /// Called before a category is deleted. Reassigns any workouts in that
    /// category to another remaining category so they don't end up with a
    /// dangling categoryId. If no other category exists, an "Uncategorized"
    /// category is created first.
    static func onCategoryDeleted(_ categoryId: UUID) {
        let categoryStore = CategoryStore.shared
        let library = WorkoutLibraryStore.shared

        let workoutsInCategory = library.templates.filter { $0.categoryId == categoryId }
        guard !workoutsInCategory.isEmpty else { return }

        let replacementId: UUID
        if let fallback = categoryStore.sortedCategories.first(where: { $0.id != categoryId }) {
            replacementId = fallback.id
        } else {
            categoryStore.add(name: "Uncategorized")
            guard let created = categoryStore.category(named: "Uncategorized") else { return }
            replacementId = created.id
        }

        let updated = library.templates.map { template -> WorkoutTemplate in
            guard template.categoryId == categoryId else { return template }
            return WorkoutTemplate(
                id: template.id,
                name: template.name,
                categoryId: replacementId,
                exercises: template.exercises,
                iconName: template.iconName
            )
        }
        library.replaceAll(with: updated)
    }

    /// Called before a machine is deleted. Clears the `machineId` on every
    /// library exercise that referenced it. The exercise itself is kept so
    /// workouts and history continue to resolve.
    static func onMachineDeleted(_ machineId: UUID) {
        let exerciseStore = ExerciseStore.shared
        let affectedExerciseIds = Set(exerciseStore.exercises.filter { $0.machineId == machineId }.map(\.id))
        guard !affectedExerciseIds.isEmpty else { return }
        let updated = exerciseStore.exercises.map { ex -> Exercise in
            guard ex.machineId == machineId else { return ex }
            return Exercise(id: ex.id, name: ex.name, machineId: nil)
        }
        exerciseStore.replaceAll(with: updated)
        WeightLogStore.shared.recalculatePersonalRecords(for: affectedExerciseIds)
    }
}
