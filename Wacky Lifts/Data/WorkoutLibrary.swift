import Foundation

enum WorkoutLibrary {
    /// Helper to get category ID by name, creating if needed
    private static func categoryId(for name: String) -> UUID {
        CategoryStore.shared.migrateCategory(fromName: name) ?? UUID()
    }

    /// Shorthand for cable/selectorized machine ID
    private static var cable: UUID { WeightMachine.standardCableMachineId }
    /// Shorthand for standard plates (barbell) machine ID
    private static var plates: UUID { WeightMachine.standardPlatesId }
    /// Shorthand for standard dumbbells machine ID
    private static var db: UUID { WeightMachine.standardDumbbellsId }
    /// Shorthand for bodyweight machine ID
    private static var bw: UUID { WeightMachine.bodyweightId }

    static var templates: [WorkoutTemplate] {
        [
            // Classic 3-Day Bodybuilder Split
            WorkoutTemplate(
                name: "Chest, Shoulders & Triceps",
                categoryId: categoryId(for: "Classic 3-Day"),
                exercises: [
                    .init(name: "Bench Press (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Incline Bench Press (Dumbbell)", sets: "3", reps: "8–12", machineId: db),
                    .init(name: "Shoulder Press (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Cable Crossover Fly", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Lateral Raise (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Triceps Rope Pushdown", sets: "3", reps: "12–15", machineId: cable),
                ],
                iconName: "figure.strengthtraining.traditional"
            ),
            WorkoutTemplate(
                name: "Back & Biceps",
                categoryId: categoryId(for: "Classic 3-Day"),
                exercises: [
                    .init(name: "Bent Over Row (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Lat Pulldown (Cable)", sets: "3", reps: "8–12", machineId: cable),
                    .init(name: "Seated Cable Row – V Grip", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Shrug (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Bicep Curl (Barbell)", sets: "3", reps: "12–15", machineId: plates),
                    .init(name: "Hammer Curl (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Face Pull", sets: "3", reps: "15–20", machineId: cable),
                ],
                iconName: "figure.strengthtraining.functional"
            ),
            WorkoutTemplate(
                name: "Legs & Abs",
                categoryId: categoryId(for: "Classic 3-Day"),
                exercises: [
                    .init(name: "Squat (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Romanian Deadlift (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Leg Extension (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Seated Leg Curl (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Seated Calf Raise (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Cable Crunch", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Leg Raise Variation", sets: "3", reps: "15–20", machineId: bw),
                ],
                iconName: "figure.core.training"
            ),

            // Push / Pull / Legs
            WorkoutTemplate(
                name: "Push",
                categoryId: categoryId(for: "Push / Pull / Legs"),
                exercises: [
                    .init(name: "Bench Press (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Incline Bench Press (Dumbbell)", sets: "3", reps: "8–12", machineId: db),
                    .init(name: "Shoulder Press (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Cable Crossover Fly", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Lateral Raise (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Triceps Rope Pushdown", sets: "3", reps: "12–15", machineId: cable),
                ],
                iconName: "dumbbell"
            ),
            WorkoutTemplate(
                name: "Pull",
                categoryId: categoryId(for: "Push / Pull / Legs"),
                exercises: [
                    .init(name: "Bent Over Row (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Lat Pulldown (Cable)", sets: "3", reps: "8–12", machineId: cable),
                    .init(name: "Seated Cable Row – V Grip", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Shrug (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Bicep Curl (Barbell)", sets: "3", reps: "12–15", machineId: plates),
                    .init(name: "Hammer Curl (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Face Pull", sets: "3", reps: "15–20", machineId: cable),
                ],
                iconName: "figure.strengthtraining.traditional"
            ),
            WorkoutTemplate(
                name: "Legs",
                categoryId: categoryId(for: "Push / Pull / Legs"),
                exercises: [
                    .init(name: "Squat (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Romanian Deadlift (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Leg Extension (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Seated Leg Curl (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Seated Calf Raise (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Cable Crunch", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Lying Leg Raise", sets: "3", reps: "15–20", machineId: bw),
                ],
                iconName: "figure.strengthtraining.functional"
            ),

            // Upper / Lower
            WorkoutTemplate(
                name: "Upper",
                categoryId: categoryId(for: "Upper / Lower"),
                exercises: [
                    .init(name: "Bench Press (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Bent Over Row (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Lat Pulldown (Cable)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Shoulder Press (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Lateral Raise (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Bicep Curl (Barbell)", sets: "3", reps: "12–15", machineId: plates),
                    .init(name: "Hammer Curl (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Triceps Rope Pushdown", sets: "3", reps: "12–15", machineId: cable),
                ],
                iconName: "dumbbell"
            ),
            WorkoutTemplate(
                name: "Lower",
                categoryId: categoryId(for: "Upper / Lower"),
                exercises: [
                    .init(name: "Squat (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Romanian Deadlift (Barbell)", sets: "3", reps: "8–10", machineId: plates),
                    .init(name: "Leg Press (Machine)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Lying Leg Curl (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Standing Calf Raise (Machine)", sets: "3", reps: "15–20", machineId: cable),
                ],
                iconName: "figure.strengthtraining.functional"
            ),

            // Upper / Lower / Upper
            WorkoutTemplate(
                name: "Upper 1",
                categoryId: categoryId(for: "Upper / Lower / Upper"),
                exercises: [
                    .init(name: "Bench Press (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Bent Over Row (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Shoulder Press (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Seated Cable Row – V Grip", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Shrug (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Lateral Raise (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Face Pull", sets: "3", reps: "15–20", machineId: cable),
                ],
                iconName: "dumbbell"
            ),
            WorkoutTemplate(
                name: "Lower",
                categoryId: categoryId(for: "Upper / Lower / Upper"),
                exercises: [
                    .init(name: "Squat (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Romanian Deadlift (Barbell)", sets: "3", reps: "8–10", machineId: plates),
                    .init(name: "Leg Press (Machine)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Lying Leg Curl (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Standing Calf Raise (Machine)", sets: "3", reps: "15–20", machineId: cable),
                ],
                iconName: "figure.strengthtraining.functional"
            ),
            WorkoutTemplate(
                name: "Upper 2",
                categoryId: categoryId(for: "Upper / Lower / Upper"),
                exercises: [
                    .init(name: "Pull Up", sets: "3", reps: "5–10", machineId: bw),
                    .init(name: "Incline Bench Press (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Lat Pulldown (Cable)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Bicep Curl (Barbell)", sets: "3", reps: "12–15", machineId: plates),
                    .init(name: "Hammer Curl (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Triceps Rope Pushdown", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Triceps Extension (Dumbbell)", sets: "3", reps: "15–20", machineId: db),
                ],
                iconName: "figure.strengthtraining.functional"
            ),

            // Full Body 1 / 2 / 3
            WorkoutTemplate(
                name: "Full Body 1",
                categoryId: categoryId(for: "Full Body"),
                exercises: [
                    .init(name: "Lat Pulldown (Cable)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Squat (Barbell)", sets: "3", reps: "10–12", machineId: plates),
                    .init(name: "Seated Cable Row – V Grip", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Incline Bench Press (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Lying Leg Curl (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Hammer Curl (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Triceps Rope Pushdown", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Lateral Raise (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                ],
                iconName: "figure.cross.training"
            ),
            WorkoutTemplate(
                name: "Full Body 2",
                categoryId: categoryId(for: "Full Body"),
                exercises: [
                    .init(name: "Overhead Press (Barbell)", sets: "3", reps: "6–10", machineId: plates),
                    .init(name: "Bent Over Row (Barbell)", sets: "3", reps: "8–10", machineId: plates),
                    .init(name: "Romanian Deadlift (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Leg Press (Machine)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Cable Fly Crossovers", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Triceps Extension (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Bicep Curl (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Seated Calf Raise", sets: "3", reps: "15–20", machineId: cable),
                ],
                iconName: "bolt.fill"
            ),
            WorkoutTemplate(
                name: "Full Body 3",
                categoryId: categoryId(for: "Full Body"),
                exercises: [
                    .init(name: "Bulgarian Split Squat", sets: "3", reps: "10–12 per leg", machineId: db),
                    .init(name: "Reverse Grip Lat Pulldown (Cable)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Chest Press (Machine)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Shrug (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                    .init(name: "Face Pull", sets: "3", reps: "15–20", machineId: cable),
                    .init(name: "Standing Calf Raise (Machine)", sets: "3", reps: "15–20", machineId: cable),
                    .init(name: "Cable Crunch", sets: "3", reps: "15–20", machineId: cable),
                ],
                iconName: "figure.cross.training"
            ),

            // Upper / Lower / Full Body
            WorkoutTemplate(
                name: "Upper Body",
                categoryId: categoryId(for: "Upper / Lower / Full Body"),
                exercises: [
                    .init(name: "Bench Press (Barbell)", sets: "3", reps: "8–10", machineId: plates),
                    .init(name: "Bent Over Row (Barbell)", sets: "3", reps: "8–10", machineId: plates),
                    .init(name: "Shoulder Press (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Seated Cable Row", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Lateral Raise (Dumbbell)", sets: "3", reps: "12–15", machineId: db),
                ],
                iconName: "dumbbell"
            ),
            WorkoutTemplate(
                name: "Lower Body",
                categoryId: categoryId(for: "Upper / Lower / Full Body"),
                exercises: [
                    .init(name: "Leg Press (Machine)", sets: "3", reps: "8–10", machineId: cable),
                    .init(name: "Glute Ham Raise", sets: "3", reps: "8–12", machineId: bw),
                    .init(name: "Leg Extension (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Seated Leg Curl (Machine)", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "Standing Calf Raise (Machine)", sets: "3", reps: "12–15", machineId: cable),
                ],
                iconName: "figure.strengthtraining.functional"
            ),
            WorkoutTemplate(
                name: "Full Body",
                categoryId: categoryId(for: "Upper / Lower / Full Body"),
                exercises: [
                    .init(name: "Incline Bench Press (Dumbbell)", sets: "3", reps: "10–12", machineId: db),
                    .init(name: "Bulgarian Split Squat", sets: "3", reps: "10–12 per leg", machineId: db),
                    .init(name: "Lat Pulldown (Cable)", sets: "3", reps: "10–12", machineId: cable),
                    .init(name: "Triceps Rope Pushdown", sets: "3", reps: "12–15", machineId: cable),
                    .init(name: "EZ Bar Biceps Curl", sets: "3", reps: "12–15", machineId: plates),
                ],
                iconName: "figure.cross.training"
            ),

            // Cardio
            WorkoutTemplate(
                name: "HIIT Circuit",
                categoryId: categoryId(for: "Cardio"),
                exercises: [
                    .init(name: "Jump Rope Warm-Up", sets: "", reps: "", duration: "3 min", machineId: bw),
                    .init(name: "Burpees", sets: "4", reps: "15", machineId: bw),
                    .init(name: "Mountain Climbers", sets: "4", reps: "20 per side", machineId: bw),
                    .init(name: "Box Jumps", sets: "4", reps: "12", machineId: bw),
                    .init(name: "Battle Ropes", sets: "4", reps: "", duration: "30 sec", machineId: bw),
                    .init(name: "Cooldown Walk", sets: "", reps: "", duration: "5 min", machineId: bw),
                ],
                iconName: "figure.highintensity.intervaltraining"
            ),
            WorkoutTemplate(
                name: "Steady State Run",
                categoryId: categoryId(for: "Cardio"),
                exercises: [
                    .init(name: "Easy Jog Warm-Up", sets: "", reps: "", duration: "5 min", machineId: bw),
                    .init(name: "Steady Pace Run", sets: "", reps: "", duration: "25 min", machineId: bw),
                    .init(name: "Cooldown Walk", sets: "", reps: "", duration: "5 min", machineId: bw),
                ],
                iconName: "figure.run"
            ),
            WorkoutTemplate(
                name: "Sprint Intervals",
                categoryId: categoryId(for: "Cardio"),
                exercises: [
                    .init(name: "Light Jog Warm-Up", sets: "", reps: "", duration: "5 min", machineId: bw),
                    .init(name: "Sprint", sets: "8", reps: "", duration: "30 sec", machineId: bw),
                    .init(name: "Recovery Jog", sets: "8", reps: "", duration: "60 sec", machineId: bw),
                    .init(name: "Cooldown Walk", sets: "", reps: "", duration: "5 min", machineId: bw),
                ],
                iconName: "figure.run"
            ),
            WorkoutTemplate(
                name: "Cycling Endurance",
                categoryId: categoryId(for: "Cardio"),
                exercises: [
                    .init(name: "Easy Spin Warm-Up", sets: "", reps: "", duration: "5 min", machineId: bw),
                    .init(name: "Moderate Pace Cycling", sets: "", reps: "", duration: "20 min", machineId: bw),
                    .init(name: "High Resistance Climb", sets: "3", reps: "", duration: "2 min", machineId: bw),
                    .init(name: "Recovery Spin", sets: "3", reps: "", duration: "1 min", machineId: bw),
                    .init(name: "Cooldown Spin", sets: "", reps: "", duration: "5 min", machineId: bw),
                ],
                iconName: "figure.indoor.cycle"
            ),
        ]
    }

    static var categorized: [UUID: [WorkoutTemplate]] {
        Dictionary(grouping: templates, by: { $0.categoryId })
    }
}
