import Foundation

enum StreakMode: Int, CaseIterable, Codable {
    case perDay = 0
    case perWeek = 1

    var title: String {
        switch self {
        case .perDay: return "Per Day"
        case .perWeek: return "Per Week"
        }
    }

    func description(weeklyGoal: Int = 1) -> String {
        switch self {
        case .perDay: return "Complete at least 1 exercise daily"
        case .perWeek:
            if weeklyGoal == 1 {
                return "Complete at least 1 workout weekly"
            } else {
                return "Complete at least \(weeklyGoal) workouts weekly"
            }
        }
    }

    var unitName: String {
        switch self {
        case .perDay: return "days"
        case .perWeek: return "weeks"
        }
    }
}

final class StreakStore {
    static let shared = StreakStore()

    static let streakDidChangeNotification = Notification.Name("StreakStore.streakDidChange")

    private let userDefaults = UserDefaults.standard
    private let currentStreakKey = "current_streak"
    private let longestStreakKey = "longest_streak"
    private let lastActivityDateKey = "last_activity_date"
    private let totalCompletedExercisesKey = "total_completed_exercises"
    private let totalCompletedWorkoutsKey = "total_completed_workouts"
    private let activeDatesKey = "active_dates"
    private let activeWeeksKey = "active_weeks"
    private let workoutDatesKey = "workout_completion_dates"
    private let weeklyWorkoutsKey = "weekly_workouts"
    private let streakModeKey = "streak_mode"
    private let weeklyWorkoutGoalKey = "weekly_workout_goal"
    private let countedActivityDatesKey = "counted_activity_dates_for_streak"
    private let countedWorkoutDatesKey = "counted_workout_dates_for_streak"
    private let exerciseCountsByDateKey = "exercise_counts_by_date"

    private(set) var currentStreak: Int {
        didSet {
            userDefaults.set(currentStreak, forKey: currentStreakKey)
            if currentStreak > longestStreak {
                longestStreak = currentStreak
            }
        }
    }

    private(set) var longestStreak: Int {
        didSet {
            userDefaults.set(longestStreak, forKey: longestStreakKey)
        }
    }

    private(set) var lastActivityDate: Date? {
        didSet {
            if let date = lastActivityDate {
                userDefaults.set(date, forKey: lastActivityDateKey)
            } else {
                userDefaults.removeObject(forKey: lastActivityDateKey)
            }
        }
    }

    private(set) var totalCompletedExercises: Int {
        didSet {
            userDefaults.set(totalCompletedExercises, forKey: totalCompletedExercisesKey)
        }
    }

    private(set) var totalCompletedWorkouts: Int {
        didSet {
            userDefaults.set(totalCompletedWorkouts, forKey: totalCompletedWorkoutsKey)
        }
    }

    private var activeDates: Set<String> {
        didSet {
            userDefaults.set(Array(activeDates), forKey: activeDatesKey)
        }
    }

    private var activeWeeks: Set<String> {
        didSet {
            userDefaults.set(Array(activeWeeks), forKey: activeWeeksKey)
        }
    }

    private var workoutDates: Set<String> {
        didSet {
            userDefaults.set(Array(workoutDates), forKey: workoutDatesKey)
        }
    }

    private var countedActivityDates: Set<String> {
        didSet {
            userDefaults.set(Array(countedActivityDates), forKey: countedActivityDatesKey)
        }
    }

    private var countedWorkoutDates: Set<String> {
        didSet {
            userDefaults.set(Array(countedWorkoutDates), forKey: countedWorkoutDatesKey)
        }
    }

    /// Tracks workout count per week (key: "yyyy-Www", value: count)
    private var weeklyWorkouts: [String: Int] {
        didSet {
            userDefaults.set(weeklyWorkouts, forKey: weeklyWorkoutsKey)
        }
    }

    /// Tracks exercise completion count per date (key: "yyyy-MM-dd", value: count)
    private var exerciseCountsByDate: [String: Int] {
        didSet {
            userDefaults.set(exerciseCountsByDate, forKey: exerciseCountsByDateKey)
        }
    }

    var weeklyWorkoutGoal: Int {
        didSet {
            userDefaults.set(weeklyWorkoutGoal, forKey: weeklyWorkoutGoalKey)
            notifyChange()
        }
    }

    var streakMode: StreakMode {
        didSet {
            userDefaults.set(streakMode.rawValue, forKey: streakModeKey)
            validateStreak()
            notifyChange()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-'W'ww"
        return formatter
    }()

    private init() {
        currentStreak = userDefaults.integer(forKey: currentStreakKey)
        longestStreak = userDefaults.integer(forKey: longestStreakKey)
        lastActivityDate = userDefaults.object(forKey: lastActivityDateKey) as? Date
        totalCompletedExercises = userDefaults.integer(forKey: totalCompletedExercisesKey)
        totalCompletedWorkouts = userDefaults.integer(forKey: totalCompletedWorkoutsKey)
        streakMode = StreakMode(rawValue: userDefaults.integer(forKey: streakModeKey)) ?? .perDay

        let savedGoal = userDefaults.integer(forKey: weeklyWorkoutGoalKey)
        weeklyWorkoutGoal = savedGoal > 0 ? savedGoal : 1

        if let stored = userDefaults.stringArray(forKey: activeDatesKey) {
            activeDates = Set(stored)
        } else {
            activeDates = []
        }

        if let stored = userDefaults.stringArray(forKey: activeWeeksKey) {
            activeWeeks = Set(stored)
        } else {
            activeWeeks = []
        }

        if let stored = userDefaults.stringArray(forKey: workoutDatesKey) {
            workoutDates = Set(stored)
        } else {
            workoutDates = []
        }

        if let stored = userDefaults.stringArray(forKey: countedActivityDatesKey) {
            countedActivityDates = Set(stored)
        } else {
            countedActivityDates = activeDates
        }

        if let stored = userDefaults.stringArray(forKey: countedWorkoutDatesKey) {
            countedWorkoutDates = Set(stored)
        } else {
            countedWorkoutDates = workoutDates
        }

        if let stored = userDefaults.dictionary(forKey: weeklyWorkoutsKey) as? [String: Int] {
            weeklyWorkouts = stored
        } else {
            weeklyWorkouts = [:]
        }

        if let stored = userDefaults.dictionary(forKey: exerciseCountsByDateKey) as? [String: Int] {
            exerciseCountsByDate = stored
        } else {
            // Backfill from CompletionStore for existing users
            exerciseCountsByDate = Self.backfillExerciseCountsFromCompletions()
        }

        repairWeeklyWorkouts()
        validateStreak()
    }

    /// Backfill exercise counts per date from CompletionStore's current entries
    private static func backfillExerciseCountsFromCompletions() -> [String: Int] {
        let completions = UserDefaults.standard.stringArray(forKey: "exercise_completions") ?? []
        var counts: [String: Int] = [:]
        for key in completions {
            let dateString = String(key.prefix(10)) // "yyyy-MM-dd"
            counts[dateString, default: 0] += 1
        }
        return counts
    }

    /// Rebuild weeklyWorkouts from countedWorkoutDates to fix any corrupted counts
    private func repairWeeklyWorkouts() {
        var rebuilt: [String: Int] = [:]
        for dateString in countedWorkoutDates {
            guard let date = Self.dateFormatter.date(from: dateString) else { continue }
            let weekString = Self.weekFormatter.string(from: date)
            rebuilt[weekString, default: 0] += 1
        }
        if rebuilt != weeklyWorkouts {
            weeklyWorkouts = rebuilt
        }
    }

    private func validateStreak() {
        switch streakMode {
        case .perDay:
            validateDayStreak()
        case .perWeek:
            validateWeekStreak()
        }
    }

    private func validateDayStreak() {
        guard let lastDate = lastActivityDate else {
            currentStreak = 0
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: lastDate)
        let daysDifference = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

        if daysDifference > 1 {
            currentStreak = 0
        }
    }

    private func validateWeekStreak() {
        guard let lastDate = lastActivityDate else {
            currentStreak = 0
            return
        }

        let calendar = Calendar.current
        let currentWeek = calendar.component(.weekOfYear, from: Date())
        let currentYear = calendar.component(.yearForWeekOfYear, from: Date())
        let lastWeek = calendar.component(.weekOfYear, from: lastDate)
        let lastYear = calendar.component(.yearForWeekOfYear, from: lastDate)

        let weeksDifference = (currentYear - lastYear) * 52 + (currentWeek - lastWeek)

        if weeksDifference > 1 {
            currentStreak = 0
        }
    }

    func recordExerciseCompletion(on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        let weekString = Self.weekFormatter.string(from: date)
        let wasNewDayForStreak = !countedActivityDates.contains(dateString)

        activeDates.insert(dateString)
        activeWeeks.insert(weekString)

        if wasNewDayForStreak {
            countedActivityDates.insert(dateString)
        }

        if streakMode == .perDay && wasNewDayForStreak {
            updateDayStreak(for: date)
        }
        // Note: perWeek streaks are updated via recordWorkoutCompletion when goal is met

        totalCompletedExercises += 1
        exerciseCountsByDate[dateString, default: 0] += 1
        notifyChange()
    }

    func recordExerciseUncompletion(on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        totalCompletedExercises = max(0, totalCompletedExercises - 1)
        if let current = exerciseCountsByDate[dateString], current > 1 {
            exerciseCountsByDate[dateString] = current - 1
        } else {
            exerciseCountsByDate.removeValue(forKey: dateString)
        }
        notifyChange()
    }

    func recordWorkoutCompletion(on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        let weekString = Self.weekFormatter.string(from: date)
        let wasNewDayForStreak = !countedWorkoutDates.contains(dateString)

        workoutDates.insert(dateString)
        totalCompletedWorkouts += 1

        // Track workouts per week for weekly goal
        if wasNewDayForStreak {
            countedWorkoutDates.insert(dateString)
            let previousCount = weeklyWorkouts[weekString] ?? 0
            let newCount = previousCount + 1
            weeklyWorkouts[weekString] = newCount

            // Check if we just hit the weekly goal for the first time this week
            if streakMode == .perWeek && previousCount < weeklyWorkoutGoal && newCount >= weeklyWorkoutGoal {
                updateWeekStreak(for: date)
            }
        }

        notifyChange()
    }

    func recordWorkoutUncompletion(on date: Date, removeWorkoutDate: Bool = false) {
        let dateString = Self.dateFormatter.string(from: date)
        let weekString = Self.weekFormatter.string(from: date)
        totalCompletedWorkouts = max(0, totalCompletedWorkouts - 1)

        if countedWorkoutDates.remove(dateString) != nil {
            if let currentCount = weeklyWorkouts[weekString], currentCount > 0 {
                weeklyWorkouts[weekString] = currentCount - 1
            }
        }

        if removeWorkoutDate {
            workoutDates.remove(dateString)
        }

        notifyChange()
    }

    func removeExerciseCompletions(_ count: Int, on date: Date, removeActivityDate: Bool) {
        guard count > 0 else { return }
        let dateString = Self.dateFormatter.string(from: date)
        totalCompletedExercises = max(0, totalCompletedExercises - count)
        if let current = exerciseCountsByDate[dateString] {
            let newCount = current - count
            if newCount > 0 {
                exerciseCountsByDate[dateString] = newCount
            } else {
                exerciseCountsByDate.removeValue(forKey: dateString)
            }
        }
        if removeActivityDate {
            activeDates.remove(dateString)
            countedActivityDates.remove(dateString)
        }
        notifyChange()
    }

    func removeWorkoutCompletion(on date: Date, removeWorkoutDate: Bool) {
        totalCompletedWorkouts = max(0, totalCompletedWorkouts - 1)
        if removeWorkoutDate {
            let dateString = Self.dateFormatter.string(from: date)
            workoutDates.remove(dateString)
            if countedWorkoutDates.remove(dateString) != nil {
                let weekString = Self.weekFormatter.string(from: date)
                if let currentCount = weeklyWorkouts[weekString], currentCount > 0 {
                    weeklyWorkouts[weekString] = currentCount - 1
                }
            }
        }
        notifyChange()
    }

    func removeWorkoutDate(on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        if workoutDates.remove(dateString) != nil {
            if countedWorkoutDates.remove(dateString) != nil {
                let weekString = Self.weekFormatter.string(from: date)
                if let currentCount = weeklyWorkouts[weekString], currentCount > 0 {
                    weeklyWorkouts[weekString] = currentCount - 1
                }
            }
            notifyChange()
        }
    }

    private func updateDayStreak(for date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        if let lastDate = lastActivityDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysDifference = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            if daysDifference == 0 {
                // Same day, streak unchanged
            } else if daysDifference == 1 {
                currentStreak += 1
            } else if daysDifference > 1 {
                currentStreak = 1
            } else if daysDifference < 0 {
                return
            }
        } else {
            currentStreak = 1
        }

        lastActivityDate = date
    }

    private func updateWeekStreak(for date: Date) {
        let calendar = Calendar.current

        if let lastDate = lastActivityDate {
            let currentWeek = calendar.component(.weekOfYear, from: date)
            let currentYear = calendar.component(.yearForWeekOfYear, from: date)
            let lastWeek = calendar.component(.weekOfYear, from: lastDate)
            let lastYear = calendar.component(.yearForWeekOfYear, from: lastDate)

            let weeksDifference = (currentYear - lastYear) * 52 + (currentWeek - lastWeek)

            if weeksDifference == 0 {
                // Same week, streak unchanged
            } else if weeksDifference == 1 {
                currentStreak += 1
            } else if weeksDifference > 1 {
                currentStreak = 1
            } else if weeksDifference < 0 {
                return
            }
        } else {
            currentStreak = 1
        }

        lastActivityDate = date
    }

    var totalActiveDays: Int {
        activeDates.count
    }

    var activeDaysThisYear: Int {
        let yearPrefix = String(Calendar.current.component(.year, from: Date()))
        return activeDates.filter { $0.hasPrefix(yearPrefix) }.count
    }

    var completedExercisesThisYear: Int {
        let yearPrefix = String(Calendar.current.component(.year, from: Date()))
        return exerciseCountsByDate.filter { $0.key.hasPrefix(yearPrefix) }.values.reduce(0, +)
    }

    var completedExercisesThisMonth: Int {
        let prefix = String(Self.dateFormatter.string(from: Date()).prefix(7))
        return exerciseCountsByDate.filter { $0.key.hasPrefix(prefix) }.values.reduce(0, +)
    }

    var activeDaysThisMonth: Int {
        let prefix = Self.dateFormatter.string(from: Date()).prefix(7) // "yyyy-MM"
        return activeDates.filter { $0.hasPrefix(prefix) }.count
    }

    var streakUnitName: String {
        streakMode.unitName
    }

    var currentWeekWorkoutCount: Int {
        let weekString = Self.weekFormatter.string(from: Date())
        return max(0, weeklyWorkouts[weekString] ?? 0)
    }

    var streakDescription: String {
        streakMode.description(weeklyGoal: weeklyWorkoutGoal)
    }

    // MARK: - Calendar Query Methods

    /// Check if there was any exercise activity on a specific date
    func hasActivity(on date: Date) -> Bool {
        let dateString = Self.dateFormatter.string(from: date)
        return activeDates.contains(dateString)
    }

    /// Check if a full workout was completed on a specific date
    func hasCompletedWorkout(on date: Date) -> Bool {
        let dateString = Self.dateFormatter.string(from: date)
        return workoutDates.contains(dateString)
    }

    /// Get all dates with activity in a given month
    func activityDates(in month: Date) -> [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        return activeDates.compactMap { dateString -> Date? in
            guard let date = Self.dateFormatter.date(from: dateString) else { return nil }
            return monthInterval.contains(date) ? date : nil
        }.sorted()
    }

    /// Get all dates with completed workouts in a given month
    func workoutDates(in month: Date) -> [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        return workoutDates.compactMap { dateString -> Date? in
            guard let date = Self.dateFormatter.date(from: dateString) else { return nil }
            return monthInterval.contains(date) ? date : nil
        }.sorted()
    }

    /// Get all active dates (for history)
    var allActiveDates: [Date] {
        activeDates.compactMap { Self.dateFormatter.date(from: $0) }.sorted()
    }

    /// Get all workout completion dates (for history)
    var allWorkoutDates: [Date] {
        workoutDates.compactMap { Self.dateFormatter.date(from: $0) }.sorted()
    }

    // MARK: - Reset

    func resetAllStats() {
        currentStreak = 0
        longestStreak = 0
        lastActivityDate = nil
        totalCompletedExercises = 0
        totalCompletedWorkouts = 0
        activeDates = []
        activeWeeks = []
        workoutDates = []
        countedActivityDates = []
        countedWorkoutDates = []
        weeklyWorkouts = [:]
        exerciseCountsByDate = [:]

        userDefaults.removeObject(forKey: currentStreakKey)
        userDefaults.removeObject(forKey: longestStreakKey)
        userDefaults.removeObject(forKey: lastActivityDateKey)
        userDefaults.removeObject(forKey: totalCompletedExercisesKey)
        userDefaults.removeObject(forKey: totalCompletedWorkoutsKey)
        userDefaults.removeObject(forKey: activeDatesKey)
        userDefaults.removeObject(forKey: activeWeeksKey)
        userDefaults.removeObject(forKey: workoutDatesKey)
        userDefaults.removeObject(forKey: countedActivityDatesKey)
        userDefaults.removeObject(forKey: countedWorkoutDatesKey)
        userDefaults.removeObject(forKey: weeklyWorkoutsKey)
        userDefaults.removeObject(forKey: exerciseCountsByDateKey)

        notifyChange()
    }

    func resetStreakOnly() {
        currentStreak = 0
        longestStreak = 0
        lastActivityDate = nil
        countedActivityDates = []
        countedWorkoutDates = []
        weeklyWorkouts = [:]

        userDefaults.removeObject(forKey: currentStreakKey)
        userDefaults.removeObject(forKey: longestStreakKey)
        userDefaults.removeObject(forKey: lastActivityDateKey)
        userDefaults.removeObject(forKey: countedActivityDatesKey)
        userDefaults.removeObject(forKey: countedWorkoutDatesKey)
        userDefaults.removeObject(forKey: weeklyWorkoutsKey)

        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.streakDidChangeNotification, object: self)
    }
}
