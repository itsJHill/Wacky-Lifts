import Foundation

final class WeightLogStore {
    static let shared = WeightLogStore()

    static let logsDidChangeNotification = Notification.Name("WeightLogStore.logsDidChange")

    private let userDefaults = UserDefaults.standard
    private let logsKey = "exercise_weight_logs"
    private let unitKey = "preferred_weight_unit"
    private let lastCleanupKey = "weight_logs_last_cleanup"
    private let prDatesKey = "personal_record_dates"

    /// All exercise logs, keyed by composite key "date_workoutId_entryId"
    private var logs: [String: ExerciseLog] {
        didSet {
            saveLogs()
        }
    }

    /// Personal records, keyed by library exerciseId (shared across workouts)
    private var personalRecords: [UUID: ExerciseLog] {
        didSet {
            savePersonalRecords()
        }
    }

    /// Prior personal records before the most recent change, keyed by library exerciseId.
    /// Allows reverting PRs after accidental deletion (e.g., deleting a partial workout).
    private var priorPersonalRecords: [UUID: ExerciseLog] {
        didSet {
            savePriorPersonalRecords()
        }
    }

    /// Dates when PRs were hit (stored forever for gold dots)
    private var prDates: Set<String> {
        didSet {
            savePRDates()
        }
    }

    var preferredUnit: WeightUnit {
        get {
            if let rawValue = userDefaults.string(forKey: unitKey),
               let unit = WeightUnit(rawValue: rawValue) {
                return unit
            }
            return .lbs
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: unitKey)
            notifyChange()
        }
    }

    private static let dateFormatter: DateFormatter = {
        AppDateCoding.makeDateKeyFormatter()
    }()

    private init() {
        logs = [:]
        personalRecords = [:]
        priorPersonalRecords = [:]
        prDates = []
        loadLogs()
        loadPersonalRecords()
        loadPriorPersonalRecords()
        loadPRDates()
        cleanupOldLogsIfNeeded()
    }

    // MARK: - Key Generation

    /// Composite key using entryId (per-workout-entry UUID) for log uniqueness
    private func key(for entryId: UUID, in workoutId: UUID, on date: Date) -> String {
        let dateString = Self.dateFormatter.string(from: date)
        return "\(dateString)_\(workoutId.uuidString)_\(entryId.uuidString)"
    }

    // MARK: - CRUD Operations

    func log(for entryId: UUID, in workoutId: UUID, on date: Date) -> ExerciseLog? {
        let k = key(for: entryId, in: workoutId, on: date)
        return logs[k]
    }

    func saveLog(_ log: ExerciseLog) {
        let k = key(for: log.entryId, in: log.workoutId, on: log.date)

        // Use the PR status from the log (caller determines if PR should be checked)
        logs[k] = log

        // Update PR record if this is marked as a PR (keyed by library exerciseId)
        if log.isPersonalRecord {
            // Preserve the outgoing PR as the prior before replacing
            if let outgoing = personalRecords[log.exerciseId] {
                priorPersonalRecords[log.exerciseId] = outgoing
            }
            personalRecords[log.exerciseId] = log
            // Record PR date (stored forever for gold dots on calendar)
            let dateString = Self.dateFormatter.string(from: log.date)
            prDates.insert(dateString)
        }

        notifyChange()
    }

    func deleteLog(for entryId: UUID, in workoutId: UUID, on date: Date) {
        let k = key(for: entryId, in: workoutId, on: date)
        logs.removeValue(forKey: k)
        notifyChange()
    }

    /// Delete all logs for a specific workout on a specific date and recalculate PRs
    func deleteLogs(for workoutId: UUID, on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        let prefix = "\(dateString)_\(workoutId.uuidString)_"
        let removedLogs = logs.filter { $0.key.hasPrefix(prefix) }.map(\.value)
        guard !removedLogs.isEmpty else { return }

        var affectedExerciseIds = Set<UUID>()
        var affectedPRDates = Set<String>()

        for log in removedLogs {
            affectedExerciseIds.insert(log.exerciseId)
            if log.isPersonalRecord {
                affectedPRDates.insert(dateString)
            }
        }

        capturePriorPRs(for: affectedExerciseIds)

        var updatedLogs = logs.filter { !$0.key.hasPrefix(prefix) }
        var updatedRecords = personalRecords
        var updatedPRDates = prDates
        recalculatePersonalRecords(
            for: affectedExerciseIds,
            affectedPRDates: affectedPRDates,
            in: &updatedLogs,
            records: &updatedRecords,
            prDates: &updatedPRDates
        )

        logs = updatedLogs
        personalRecords = updatedRecords
        prDates = updatedPRDates
        notifyChange()
    }

    func deleteLogs(on date: Date) {
        let dateString = Self.dateFormatter.string(from: date)
        let removedLogs = logs.filter { $0.key.hasPrefix(dateString) }.map(\.value)
        guard !removedLogs.isEmpty else { return }

        var affectedExerciseIds = Set<UUID>()
        var affectedPRDates = Set<String>()

        for log in removedLogs {
            affectedExerciseIds.insert(log.exerciseId)
            if log.isPersonalRecord {
                affectedPRDates.insert(dateString)
            }
        }

        capturePriorPRs(for: affectedExerciseIds)

        var updatedLogs = logs.filter { !$0.key.hasPrefix(dateString) }
        var updatedRecords = personalRecords
        var updatedPRDates = prDates
        recalculatePersonalRecords(
            for: affectedExerciseIds,
            affectedPRDates: affectedPRDates,
            in: &updatedLogs,
            records: &updatedRecords,
            prDates: &updatedPRDates
        )

        logs = updatedLogs
        personalRecords = updatedRecords
        prDates = updatedPRDates
        notifyChange()
    }

    // MARK: - Prior PR Helpers

    /// Snapshot current PRs for the given exercises before recalculation
    private func capturePriorPRs(for exerciseIds: Set<UUID>) {
        for exerciseId in exerciseIds {
            if let current = personalRecords[exerciseId] {
                priorPersonalRecords[exerciseId] = current
            }
        }
    }

    // MARK: - PR Detection & Revert

    func personalRecord(for exerciseId: UUID) -> ExerciseLog? {
        personalRecords[exerciseId]
    }

    func progressionKind(for exerciseId: UUID) -> WeightProgressionKind {
        machine(for: exerciseId)?.progressionKind ?? .higherIsBetter
    }

    func displayWeight(_ weight: Double, for exerciseId: UUID, unit: WeightUnit) -> String {
        if weight < 0 {
            return "Unassisted"
        }
        if let machine = machine(for: exerciseId) {
            return machine.displayText(for: weight, unit: unit)
        }
        return Self.formatWeight(weight, unit: unit)
    }

    func bestWeight(from setWeights: [Double], for exerciseId: UUID) -> Double {
        let validWeights = setWeights.filter { isValidLogWeight($0, for: exerciseId) }
        guard !validWeights.isEmpty else { return 0 }

        switch progressionKind(for: exerciseId) {
        case .higherIsBetter:
            return validWeights.max() ?? 0
        case .lowerIsBetter:
            return validWeights.min() ?? 0
        }
    }

    /// All current personal records, sorted by date (most recent first)
    func allPersonalRecords() -> [ExerciseLog] {
        personalRecords.values.sorted { $0.date > $1.date }
    }

    /// The PR that was active before the most recent change (deletion/recalculation)
    func priorPersonalRecord(for exerciseId: UUID) -> ExerciseLog? {
        priorPersonalRecords[exerciseId]
    }

    /// Returns exercise IDs that have a prior PR different from (or missing) their current PR
    func exerciseIdsWithRevertablePRs() -> Set<UUID> {
        var result = Set<UUID>()
        for (exerciseId, priorPR) in priorPersonalRecords {
            let currentPR = personalRecords[exerciseId]
            if currentPR == nil || currentPR?.weight != priorPR.weight {
                result.insert(exerciseId)
            }
        }
        return result
    }

    /// Revert a single exercise's PR to the prior value
    func revertPR(for exerciseId: UUID) {
        guard let prior = priorPersonalRecords[exerciseId] else { return }

        personalRecords[exerciseId] = prior
        priorPersonalRecords.removeValue(forKey: exerciseId)

        // Restore the PR date
        let dateString = Self.dateFormatter.string(from: prior.date)
        prDates.insert(dateString)

        notifyChange()
    }

    /// Revert all exercises' PRs to their prior values
    func revertAllPRs() {
        for (exerciseId, prior) in priorPersonalRecords {
            personalRecords[exerciseId] = prior
            let dateString = Self.dateFormatter.string(from: prior.date)
            prDates.insert(dateString)
        }
        priorPersonalRecords = [:]
        notifyChange()
    }

    /// Dismiss stored prior PRs (accept the current state)
    func clearPriorPRs() {
        priorPersonalRecords = [:]
    }

    func isPersonalRecord(exerciseId: UUID, weight: Double) -> Bool {
        guard isValidLogWeight(weight, for: exerciseId) else { return false }

        guard let currentPR = personalRecords[exerciseId] else {
            return true // First log is always a PR
        }

        return isBetter(candidate: weight, than: currentPR.weight, for: exerciseId)
    }

    func recalculatePersonalRecords(for exerciseIds: Set<UUID>) {
        guard !exerciseIds.isEmpty else { return }

        capturePriorPRs(for: exerciseIds)

        var updatedLogs = logs
        var updatedRecords = personalRecords
        var updatedPRDates = prDates
        recalculatePersonalRecords(
            for: exerciseIds,
            in: &updatedLogs,
            records: &updatedRecords,
            prDates: &updatedPRDates
        )

        logs = updatedLogs
        personalRecords = updatedRecords
        prDates = updatedPRDates
        notifyChange()
    }

    /// Reset the PR for a specific exercise
    func resetPR(for exerciseId: UUID) {
        personalRecords.removeValue(forKey: exerciseId)
        notifyChange()
    }

    private func machine(for exerciseId: UUID) -> WeightMachine? {
        guard let machineId = ExerciseStore.shared.exercise(for: exerciseId)?.machineId else { return nil }
        return MachineStore.shared.machine(for: machineId)
    }

    private func isValidLogWeight(_ weight: Double, for exerciseId: UUID) -> Bool {
        if let machine = machine(for: exerciseId) {
            return machine.isValidLogWeight(weight)
        }
        return weight > 0
    }

    private func isBetter(candidate: Double, than current: Double, for exerciseId: UUID) -> Bool {
        guard isValidLogWeight(candidate, for: exerciseId) else { return false }
        guard isValidLogWeight(current, for: exerciseId) else { return true }

        switch progressionKind(for: exerciseId) {
        case .higherIsBetter:
            return candidate > current
        case .lowerIsBetter:
            return candidate < current
        }
    }

    private func bestLog(for exerciseId: UUID, from candidateLogs: [ExerciseLog]) -> ExerciseLog? {
        candidateLogs
            .filter { $0.exerciseId == exerciseId && isValidLogWeight($0.weight, for: exerciseId) }
            .sorted { lhs, rhs in
                if lhs.weight == rhs.weight { return lhs.date > rhs.date }
                return isBetter(candidate: lhs.weight, than: rhs.weight, for: exerciseId)
            }
            .first
    }

    private func recalculatePersonalRecords(
        for exerciseIds: Set<UUID>,
        affectedPRDates additionalAffectedPRDates: Set<String> = [],
        in updatedLogs: inout [String: ExerciseLog],
        records updatedRecords: inout [UUID: ExerciseLog],
        prDates updatedPRDates: inout Set<String>
    ) {
        var affectedPRDates = additionalAffectedPRDates

        for (logKey, log) in updatedLogs where exerciseIds.contains(log.exerciseId) {
            if log.isPersonalRecord {
                affectedPRDates.insert(Self.dateFormatter.string(from: log.date))
            }
            updatedLogs[logKey] = log.withPersonalRecord(false)
        }

        for exerciseId in exerciseIds {
            if let bestLog = bestLog(for: exerciseId, from: Array(updatedLogs.values)) {
                let newPR = bestLog.withPersonalRecord(true)
                let logKey = key(for: newPR.entryId, in: newPR.workoutId, on: newPR.date)
                updatedLogs[logKey] = newPR
                updatedRecords[exerciseId] = newPR
                updatedPRDates.insert(Self.dateFormatter.string(from: newPR.date))
            } else {
                updatedRecords.removeValue(forKey: exerciseId)
            }
        }

        for prDate in affectedPRDates {
            let hasRemainingPR = updatedLogs.values.contains { log in
                log.isPersonalRecord && Self.dateFormatter.string(from: log.date) == prDate
            }
            if !hasRemainingPR {
                updatedPRDates.remove(prDate)
            }
        }
    }

    private static func formatWeight(_ weight: Double, unit: WeightUnit) -> String {
        let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
        return "\(formatted) \(unit.symbol)"
    }

    /// Delete all logs for specific exercise entries within a workout and recalculate PRs
    func deleteLogsForExercises(_ entryIds: Set<UUID>, in workoutId: UUID) {
        guard !entryIds.isEmpty else { return }

        let removedKeys = logs.filter { _, log in
            log.workoutId == workoutId && entryIds.contains(log.entryId)
        }
        guard !removedKeys.isEmpty else { return }

        var affectedExerciseIds = Set<UUID>()
        var affectedPRDates = Set<String>()
        for (_, log) in removedKeys {
            affectedExerciseIds.insert(log.exerciseId)
            if log.isPersonalRecord {
                affectedPRDates.insert(Self.dateFormatter.string(from: log.date))
            }
        }

        capturePriorPRs(for: affectedExerciseIds)

        var updatedLogs = logs
        for key in removedKeys.keys {
            updatedLogs.removeValue(forKey: key)
        }

        var updatedRecords = personalRecords
        var updatedPRDates = prDates
        recalculatePersonalRecords(
            for: affectedExerciseIds,
            affectedPRDates: affectedPRDates,
            in: &updatedLogs,
            records: &updatedRecords,
            prDates: &updatedPRDates
        )

        logs = updatedLogs
        personalRecords = updatedRecords
        prDates = updatedPRDates
        notifyChange()
    }

    /// Delete all logs for a workout and recalculate PRs for affected exercises
    func deleteLogsAndRecalculatePRs(for workoutId: UUID) {
        // 1. Find affected exercises and dates that had PRs
        var affectedExerciseIds = Set<UUID>()
        var affectedPRDates = Set<String>()
        for (_, log) in logs where log.workoutId == workoutId {
            affectedExerciseIds.insert(log.exerciseId)
            if log.isPersonalRecord {
                affectedPRDates.insert(Self.dateFormatter.string(from: log.date))
            }
        }

        guard !affectedExerciseIds.isEmpty else { return }

        capturePriorPRs(for: affectedExerciseIds)

        // 2. Remove all logs for this workout
        var updatedLogs = logs.filter { $0.value.workoutId != workoutId }

        // 3. For each affected exercise, find the next-best PR from remaining logs
        var updatedRecords = personalRecords
        var updatedPRDates = prDates
        recalculatePersonalRecords(
            for: affectedExerciseIds,
            affectedPRDates: affectedPRDates,
            in: &updatedLogs,
            records: &updatedRecords,
            prDates: &updatedPRDates
        )

        // 5. Apply all changes
        logs = updatedLogs
        personalRecords = updatedRecords
        prDates = updatedPRDates
        notifyChange()
    }

    // MARK: - History & Lookup

    func lastWeight(for exerciseId: UUID) -> Double? {
        // Find most recent log for this exercise (by library exerciseId)
        let exerciseLogs = logs.values
            .filter { $0.exerciseId == exerciseId }
            .sorted { $0.date > $1.date }

        return exerciseLogs.first?.weight
    }

    func history(for exerciseId: UUID, limit: Int = 10) -> [ExerciseLog] {
        logs.values
            .filter { $0.exerciseId == exerciseId }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// Get all logs sorted by date (oldest first)
    func allLogs() -> [ExerciseLog] {
        logs.values
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.exerciseName < rhs.exerciseName
                }
                return lhs.date < rhs.date
            }
    }

    // MARK: - Calendar Queries

    /// Check if a PR was hit on a specific date (stored forever)
    func hasPR(on date: Date) -> Bool {
        let dateString = Self.dateFormatter.string(from: date)
        return prDates.contains(dateString)
    }

    /// Get all PR dates in a given month
    func prDates(in month: Date) -> [Date] {
        let calendar = AppDateCoding.calendar
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        return prDates.compactMap { dateString -> Date? in
            guard let date = Self.dateFormatter.date(from: dateString) else { return nil }
            return monthInterval.contains(date) ? date : nil
        }.sorted()
    }

    /// Check if there are weight logs on a specific date
    func hasLogs(on date: Date) -> Bool {
        let dateString = Self.dateFormatter.string(from: date)
        return logs.keys.contains { $0.hasPrefix(dateString) }
    }

    /// Get all weight logs for a specific date
    func logs(on date: Date) -> [ExerciseLog] {
        let dateString = Self.dateFormatter.string(from: date)
        return logs.filter { $0.key.hasPrefix(dateString) }
            .map { $0.value }
            .sorted { $0.exerciseName < $1.exerciseName }
    }

    /// Get dates with weight logs in a given month
    func logDates(in month: Date) -> [Date] {
        let calendar = AppDateCoding.calendar
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        var dates = Set<Date>()
        for log in logs.values {
            if monthInterval.contains(log.date) {
                dates.insert(calendar.startOfDay(for: log.date))
            }
        }
        return dates.sorted()
    }

    // MARK: - Migration

    /// Migrate logs and PRs from old per-entry-ID keying to library exercise ID keying.
    /// `mapping` maps old entry UUIDs → library exercise UUIDs.
    func migrateToExerciseLibrary(mapping: [UUID: UUID]) {
        guard !mapping.isEmpty else { return }

        var migratedLogs: [String: ExerciseLog] = [:]
        for (logKey, log) in logs {
            let libraryExerciseId = mapping[log.exerciseId] ?? log.exerciseId
            let migratedLog = ExerciseLog(
                id: log.id,
                entryId: log.entryId,
                exerciseId: libraryExerciseId,
                exerciseName: log.exerciseName,
                workoutId: log.workoutId,
                date: log.date,
                weight: log.weight,
                reps: log.reps,
                unit: log.unit,
                isPersonalRecord: log.isPersonalRecord,
                setWeights: log.setWeights
            )
            migratedLogs[logKey] = migratedLog
        }

        var migratedRecords: [UUID: ExerciseLog] = [:]
        var migratedPRDates = prDates
        var normalizedLogs = migratedLogs
        recalculatePersonalRecords(
            for: Set(migratedLogs.values.map(\.exerciseId)),
            in: &normalizedLogs,
            records: &migratedRecords,
            prDates: &migratedPRDates
        )

        logs = normalizedLogs
        personalRecords = migratedRecords
        prDates = migratedPRDates
        priorPersonalRecords = [:]
    }

    // MARK: - Persistence

    private func loadLogs() {
        guard let data = userDefaults.data(forKey: logsKey) else { return }

        do {
            let decoded = try JSONDecoder().decode([String: ExerciseLog].self, from: data)
            logs = decoded
        } catch {
            ErrorReporter.shared.report("Failed to load weight logs", source: "WeightLogStore.loadLogs", error: error)
        }
    }

    private func saveLogs() {
        do {
            let data = try JSONEncoder().encode(logs)
            userDefaults.set(data, forKey: logsKey)
        } catch {
            ErrorReporter.shared.report("Failed to save weight logs", source: "WeightLogStore.saveLogs", error: error)
        }
    }

    private func loadPersonalRecords() {
        guard let data = userDefaults.data(forKey: "personal_records") else { return }

        do {
            let decoded = try JSONDecoder().decode([UUID: ExerciseLog].self, from: data)
            personalRecords = decoded
        } catch {
            ErrorReporter.shared.report("Failed to load personal records", source: "WeightLogStore.loadPersonalRecords", error: error)
        }
    }

    private func savePersonalRecords() {
        do {
            let data = try JSONEncoder().encode(personalRecords)
            userDefaults.set(data, forKey: "personal_records")
        } catch {
            ErrorReporter.shared.report("Failed to save personal records", source: "WeightLogStore.savePersonalRecords", error: error)
        }
    }

    private func loadPriorPersonalRecords() {
        guard let data = userDefaults.data(forKey: "prior_personal_records") else { return }

        do {
            let decoded = try JSONDecoder().decode([UUID: ExerciseLog].self, from: data)
            priorPersonalRecords = decoded
        } catch {
            ErrorReporter.shared.report("Failed to load prior personal records", source: "WeightLogStore.loadPriorPersonalRecords", error: error)
        }
    }

    private func savePriorPersonalRecords() {
        do {
            let data = try JSONEncoder().encode(priorPersonalRecords)
            userDefaults.set(data, forKey: "prior_personal_records")
        } catch {
            ErrorReporter.shared.report("Failed to save prior personal records", source: "WeightLogStore.savePriorPersonalRecords", error: error)
        }
    }

    private func loadPRDates() {
        if let stored = userDefaults.stringArray(forKey: prDatesKey) {
            prDates = Set(stored)
        }
    }

    /// Re-read logs, records, and PR dates from UserDefaults. Called by
    /// `DataBackupManager` after import so the Streaks / history views pick
    /// up the restored data without the app needing to relaunch.
    func reloadFromDisk() {
        logs = [:]
        personalRecords = [:]
        priorPersonalRecords = [:]
        prDates = []
        loadLogs()
        loadPersonalRecords()
        loadPriorPersonalRecords()
        loadPRDates()
        notifyChange()
    }

    private func savePRDates() {
        userDefaults.set(Array(prDates), forKey: prDatesKey)
    }

    // MARK: - Cleanup (3-month retention)

    private func cleanupOldLogsIfNeeded() {
        let calendar = AppDateCoding.calendar
        let today = Date()

        // Only cleanup once per week
        if let lastCleanup = userDefaults.object(forKey: lastCleanupKey) as? Date,
           let daysSinceCleanup = calendar.dateComponents([.day], from: lastCleanup, to: today).day,
           daysSinceCleanup < 7 {
            return
        }

        // Remove logs older than 3 months
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: today) else { return }

        let oldCount = logs.count
        logs = logs.filter { _, log in
            log.date >= threeMonthsAgo
        }

        if logs.count != oldCount {
            print("Cleaned up \(oldCount - logs.count) old weight logs")
        }

        userDefaults.set(today, forKey: lastCleanupKey)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.logsDidChangeNotification, object: self)
    }

    func resetAll() {
        logs = [:]
        personalRecords = [:]
        priorPersonalRecords = [:]
        prDates = []
        userDefaults.removeObject(forKey: lastCleanupKey)
        notifyChange()
    }
}
