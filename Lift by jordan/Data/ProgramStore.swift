import Foundation

final class ProgramStore {
    static let shared = ProgramStore()

    static let programsDidChangeNotification = Notification.Name("ProgramStore.programsDidChange")
    static let activeProgramDidChangeNotification = Notification.Name("ProgramStore.activeProgramDidChange")

    private let userDefaults = UserDefaults.standard
    private let programsKey = "saved_programs"
    private let activeProgramIdKey = "active_program_id"
    private let activeProgramStartDateKey = "active_program_start_date"
    private let completedProgramsKey = "completed_programs"

    private(set) var programs: [Program] = []
    private(set) var completedPrograms: [ProgramCompletion] = []

    // MARK: - Active Program

    var activeProgramId: UUID? {
        get {
            guard let uuidString = userDefaults.string(forKey: activeProgramIdKey) else { return nil }
            return UUID(uuidString: uuidString)
        }
        set {
            if let id = newValue {
                userDefaults.set(id.uuidString, forKey: activeProgramIdKey)
            } else {
                userDefaults.removeObject(forKey: activeProgramIdKey)
            }
        }
    }

    var activeStartDate: Date? {
        get {
            guard let isoString = userDefaults.string(forKey: activeProgramStartDateKey),
                  let date = ISO8601DateFormatter().date(from: isoString) else { return nil }
            return date
        }
        set {
            if let date = newValue {
                userDefaults.set(ISO8601DateFormatter().string(from: date), forKey: activeProgramStartDateKey)
            } else {
                userDefaults.removeObject(forKey: activeProgramStartDateKey)
            }
        }
    }

    var activeProgram: Program? {
        guard let id = activeProgramId else { return nil }
        return programs.first { $0.id == id }
    }

    var hasActiveProgram: Bool {
        activeProgramId != nil
    }

    func currentWeekNumber() -> Int? {
        guard let startDate = activeStartDate else { return nil }
        return AppDateCoding.weeksBetween(startDate, and: Date())
    }

    // MARK: - Init

    private init() {
        loadPrograms()
        loadCompletedPrograms()
        loadActiveProgram()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryChange),
            name: WorkoutLibraryStore.libraryDidChangeNotification,
            object: nil
        )

        seedProgramsIfNeeded()
    }

    // MARK: - CRUD

    func add(_ program: Program) {
        programs.append(program)
        savePrograms()
        notifyChange()
    }

    func update(_ program: Program) {
        guard let index = programs.firstIndex(where: { $0.id == program.id }) else { return }
        programs[index] = program
        savePrograms()
        notifyChange()
    }

    func delete(id: UUID) {
        programs.removeAll { $0.id == id }

        if activeProgramId == id {
            deactivate(completedAllWeeks: false)
        }

        savePrograms()
        notifyChange()
    }

    func program(withId id: UUID) -> Program? {
        programs.first { $0.id == id }
    }

    // MARK: - Activation

    func activate(programId: UUID, startDate: Date) {
        guard let program = programs.first(where: { $0.id == programId }),
              !program.weeks.isEmpty else { return }

        // Deactivate any currently active program first
        if activeProgramId != nil {
            deactivate(completedAllWeeks: false)
        }

        activeProgramId = programId
        activeStartDate = AppDateCoding.startOfDay(for: startDate)

        // Populate current week's workouts into the schedule
        populateCurrentWeek()

        notifyActiveChange()
    }

    func deactivate(completedAllWeeks: Bool = false) {
        guard let program = activeProgram,
              let startDate = activeStartDate else { return }

        let completion = ProgramCompletion(
            programId: program.id,
            programName: program.name,
            startDate: startDate,
            endDate: Date(),
            totalWeeks: program.weeks.count
        )
        completedPrograms.append(completion)
        saveCompletedPrograms()

        // Clear program assignments from schedule
        ScheduleStore.shared.clearProgramAssignments()

        activeProgramId = nil
        activeStartDate = nil

        notifyChange()
        notifyActiveChange()
    }

    /// Auto-populate or clear the schedule based on the active program's current week.
    /// Called on week boundaries and when a program is activated.
    func populateCurrentWeek() {
        guard let program = activeProgram,
              let startDate = activeStartDate else {
            return
        }

        let weekNumber = currentWeekNumber()
        guard let weekNum = weekNumber,
              weekNum >= 0,
              weekNum < program.weeks.count else {
            // Past program end — auto-deactivate
            if let wn = weekNumber, wn >= program.weeks.count {
                deactivate(completedAllWeeks: true)
            }
            return
        }

        let week = program.weeks[weekNum]
        ScheduleStore.shared.populateFromProgram(week: week)
    }

    /// Resolve workouts for a program day against the current library.
    func resolveWorkouts(for day: ProgramDay) -> [WorkoutTemplate] {
        let library = WorkoutLibraryStore.shared
        return day.workoutIds.compactMap { library.template(withId: $0) }
    }

    /// Check if all program-planned exercises for a specific date are completed.
    func isDayComplete(program: Program, weekNumber: Int, weekday: Weekday, on date: Date) -> Bool {
        guard weekNumber >= 0, weekNumber < program.weeks.count else { return false }
        let week = program.weeks[weekNumber]
        guard let day = week.days.first(where: { $0.weekday == weekday }) else { return false }
        guard !day.workoutIds.isEmpty else { return false }

        let completionStore = CompletionStore.shared
        let workouts = resolveWorkouts(for: day)

        for workout in workouts {
            if !completionStore.isWorkoutFullyCompleted(workout, on: date) {
                return false
            }
        }
        return true
    }

    /// Completed week count based on actual exercise completions.
    func completedWeekCount(program: Program, startDate: Date) -> Int {
        let now = Date()
        var completed = 0
        for week in program.weeks {
            // Calculate the Sunday of the target week
            let weekDaysOffset = (week.weekNumber - 1) * 7
            guard let programWeekStart = AppDateCoding.startOfWeek(for: startDate),
                  let weekStartDate = AppDateCoding.calendar.date(byAdding: .day, value: weekDaysOffset, to: programWeekStart) else { break }
            guard weekStartDate <= now else { break }
            // Check if at least one day in this week is complete
            if let firstDay = week.days.first,
               let firstDayDate = date(for: firstDay.weekday, in: weekStartDate) {
                let allDaysComplete = week.days.allSatisfy { day in
                    guard let d = date(for: day.weekday, in: weekStartDate) else { return true }
                    // Completed if no workouts OR all workouts completed
                    return day.workoutIds.isEmpty || isDateComplete(program: program, weekNumber: week.weekNumber, on: d)
                }
                if allDaysComplete {
                    completed += 1
                }
            }
        }
        return completed
    }

    private func isDateComplete(program: Program, weekNumber: Int, on date: Date) -> Bool {
        // Check if all scheduled days in this week have all program workouts completed
        guard weekNumber >= 0, weekNumber < program.weeks.count else { return false }
        let week = program.weeks[weekNumber]
        let completionStore = CompletionStore.shared
        for day in week.days {
            guard !day.workoutIds.isEmpty else { continue }
            let workouts = resolveWorkouts(for: day)
            for workout in workouts {
                if !completionStore.isWorkoutFullyCompleted(workout, on: date) {
                    return false
                }
            }
        }
        return true
    }

    /// Get the date for a specific weekday within a given week.
    private func date(for weekday: Weekday, in weekStart: Date) -> Date? {
        let isoWeekday = weekday.rawValue // 1=Sunday ... 7=Saturday
        return AppDateCoding.calendar.date(byAdding: .day, value: isoWeekday - 1, to: weekStart)
    }

    // MARK: - Library refresh

    @objc private func handleLibraryChange() {
        // Programs reference templates by UUID; no structural change needed
        // since templates are resolved on-the-fly. Just notify to update UI.
        notifyChange()
    }

    // MARK: - Seeding

    private let programsInitializedKey = "programs_initialized"

    private func seedProgramsIfNeeded() {
        guard programs.isEmpty else { return }

        let library = WorkoutLibraryStore.shared

        func findTemplate(_ name: String) -> UUID? {
            library.templates.first(where: { $0.name == name })?.id
        }

        func day(_ weekday: Weekday, _ names: String...) -> ProgramDay {
            let ids = names.compactMap { findTemplate($0) }
            return ProgramDay(weekday: weekday, workoutIds: ids)
        }

        let program = Program(
            name: "Jeff Nippard PPL+ Hybrid",
            weeks: [
                // ---- Weeks 1-2: Foundation ----
                ProgramWeek(weekNumber: 1, days: [
                    day(.monday, "Upper"),
                    day(.tuesday, "Steady State Run"),
                    day(.wednesday, "Lower"),
                    day(.thursday, "Cycling Endurance"),
                    day(.friday, "Full Body 1"),
                    day(.saturday, "Upper 1", "HIIT Circuit"),
                ], notes: "Foundation: Find your working weights. Leave 1-2 RIR. Focus on technique."),

                ProgramWeek(weekNumber: 2, days: [
                    day(.monday, "Upper"),
                    day(.tuesday, "Steady State Run"),
                    day(.wednesday, "Lower"),
                    day(.thursday, "Cycling Endurance"),
                    day(.friday, "Full Body 1"),
                    day(.saturday, "Upper 1", "HIIT Circuit"),
                ], notes: "Foundation: Find your working weights. Leave 1-2 RIR. Focus on technique."),

                // ---- Weeks 3-4: Overload ----
                ProgramWeek(weekNumber: 3, days: [
                    day(.monday, "Upper 1"),
                    day(.tuesday, "Sprint Intervals"),
                    day(.wednesday, "Lower"),
                    day(.thursday, "Steady State Run"),
                    day(.friday, "Full Body 2"),
                    day(.saturday, "Upper 2", "Cycling Endurance"),
                ], notes: "Overload: Add 5 lbs to compounds, 2.5 lbs to isolations. 0-1 RIR on last set."),

                ProgramWeek(weekNumber: 4, days: [
                    day(.monday, "Upper 1"),
                    day(.tuesday, "Sprint Intervals"),
                    day(.wednesday, "Lower"),
                    day(.thursday, "Steady State Run"),
                    day(.friday, "Full Body 2"),
                    day(.saturday, "Upper 2", "Cycling Endurance"),
                ], notes: "Overload: Add 5 lbs to compounds, 2.5 lbs to isolations. 0-1 RIR on last set."),

                // ---- Weeks 5-6: Peak ----
                ProgramWeek(weekNumber: 5, days: [
                    day(.monday, "Upper 1"),
                    day(.tuesday, "Sprint Intervals"),
                    day(.wednesday, "Lower"),
                    day(.thursday, "HIIT Circuit"),
                    day(.friday, "Full Body 3"),
                    day(.saturday, "Upper 2", "Steady State Run"),
                ], notes: "Peak: Push to failure on final sets. Attempt new PRs on compounds."),

                ProgramWeek(weekNumber: 6, days: [
                    day(.monday, "Upper 1"),
                    day(.tuesday, "Sprint Intervals"),
                    day(.wednesday, "Lower"),
                    day(.thursday, "HIIT Circuit"),
                    day(.friday, "Full Body 3"),
                    day(.saturday, "Upper 2", "Steady State Run"),
                ], notes: "Peak: Push to failure on final sets. Attempt new PRs on compounds. Prepare for deload next week."),
            ]
        )

        programs.append(program)
        savePrograms()
        userDefaults.set(true, forKey: programsInitializedKey)
        notifyChange()
    }

    private func loadPrograms() {
        guard let data = userDefaults.data(forKey: programsKey) else { return }
        do {
            programs = try JSONDecoder().decode([Program].self, from: data)
        } catch {
            ErrorReporter.shared.report("Failed to load programs", source: "ProgramStore.loadPrograms", error: error)
        }
    }

    private func savePrograms() {
        do {
            let data = try JSONEncoder().encode(programs)
            userDefaults.set(data, forKey: programsKey)
        } catch {
            ErrorReporter.shared.report("Failed to save programs", source: "ProgramStore.savePrograms", error: error)
        }
    }

    private func loadCompletedPrograms() {
        guard let data = userDefaults.data(forKey: completedProgramsKey) else { return }
        do {
            completedPrograms = try JSONDecoder().decode([ProgramCompletion].self, from: data)
        } catch {
            ErrorReporter.shared.report("Failed to load completed programs", source: "ProgramStore.loadCompletedPrograms", error: error)
        }
    }

    private func saveCompletedPrograms() {
        do {
            let data = try JSONEncoder().encode(completedPrograms)
            userDefaults.set(data, forKey: completedProgramsKey)
        } catch {
            ErrorReporter.shared.report("Failed to save completed programs", source: "ProgramStore.saveCompletedPrograms", error: error)
        }
    }

    private func loadActiveProgram() {
        guard activeProgramId != nil, activeStartDate != nil else { return }

        // Verify the program still exists in saved programs
        guard let program = activeProgram else {
            activeProgramId = nil
            activeStartDate = nil
            return
        }

        // Check week boundary — if we passed the end, deactivate
        let weekNum = currentWeekNumber()
        if let wn = weekNum, wn >= program.weeks.count {
            deactivate(completedAllWeeks: true)
        }
    }

    func reloadFromDisk() {
        loadPrograms()
        loadCompletedPrograms()
        loadActiveProgram()
        notifyChange()
        notifyActiveChange()
    }

    func resetAll() {
        programs = []
        completedPrograms = []
        activeProgramId = nil
        activeStartDate = nil
        userDefaults.removeObject(forKey: programsKey)
        userDefaults.removeObject(forKey: completedProgramsKey)
        userDefaults.removeObject(forKey: activeProgramIdKey)
        userDefaults.removeObject(forKey: activeProgramStartDateKey)
        ScheduleStore.shared.clearProgramAssignments()
        notifyChange()
        notifyActiveChange()
    }

    // MARK: - Notifications

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.programsDidChangeNotification, object: self)
    }

    private func notifyActiveChange() {
        NotificationCenter.default.post(name: Self.activeProgramDidChangeNotification, object: self)
    }
}
