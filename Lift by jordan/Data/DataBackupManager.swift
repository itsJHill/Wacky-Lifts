import Foundation

final class DataBackupManager {
    static let shared = DataBackupManager()
    private let userDefaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Every UserDefaults key the app uses, grouped by type for encoding.
    /// Keys storing JSON Data (Codable objects encoded via JSONEncoder):
    private let jsonDataKeys: [String] = [
        "workout_library",
        "exercise_library",
        "weekly_schedule",
        "weekly_schedule_previous",
        "workout_categories",
        "weight_machines",
        "exercise_weight_logs",
        "personal_records",
        "prior_personal_records",
        "workout_snapshots",
    ]

    /// Keys storing simple string arrays:
    private let stringArrayKeys: [String] = [
        "exercise_completions",
        "active_dates",
        "active_weeks",
        "workout_completion_dates",
        "counted_activity_dates_for_streak",
        "counted_workout_dates_for_streak",
        "personal_record_dates",
    ]

    /// Keys storing string values:
    private let stringKeys: [String] = [
        "preferred_weight_unit",
        "schedule_week_identifier",
        "user_display_name",
    ]

    /// Keys storing integer values:
    private let integerKeys: [String] = [
        "app_theme",
        "current_streak",
        "longest_streak",
        "total_completed_exercises",
        "total_completed_workouts",
        "streak_mode",
        "weekly_workout_goal",
    ]

    /// Keys storing boolean values:
    private let boolKeys: [String] = [
        "workout_library_initialized",
        "exercise_library_migrated",
    ]

    /// Keys storing Date values:
    private let dateKeys: [String] = [
        "last_activity_date",
        "weight_logs_last_cleanup",
        "workout_snapshots_last_cleanup",
    ]

    /// Keys storing [String: Int] dictionaries:
    private let stringIntDictKeys: [String] = [
        "weekly_workouts",
        "exercise_counts_by_date",
    ]

    private init() {}

    // MARK: - Export

    func exportBackup() throws -> Data {
        var backup: [String: Any] = [:]
        backup["backup_version"] = 1
        backup["backup_date"] = ISO8601DateFormatter().string(from: Date())
        backup["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        // JSON Data keys — re-encode the raw Data as base64 so it survives JSON round-trip
        var jsonDataSection: [String: String] = [:]
        for key in jsonDataKeys {
            if let data = userDefaults.data(forKey: key) {
                jsonDataSection[key] = data.base64EncodedString()
            }
        }
        backup["json_data"] = jsonDataSection

        // String arrays
        var stringArraySection: [String: [String]] = [:]
        for key in stringArrayKeys {
            if let array = userDefaults.stringArray(forKey: key) {
                stringArraySection[key] = array
            }
        }
        backup["string_arrays"] = stringArraySection

        // Strings
        var stringSection: [String: String] = [:]
        for key in stringKeys {
            if let value = userDefaults.string(forKey: key) {
                stringSection[key] = value
            }
        }
        backup["strings"] = stringSection

        // Integers
        var intSection: [String: Int] = [:]
        for key in integerKeys {
            if userDefaults.object(forKey: key) != nil {
                intSection[key] = userDefaults.integer(forKey: key)
            }
        }
        backup["integers"] = intSection

        // Booleans
        var boolSection: [String: Bool] = [:]
        for key in boolKeys {
            if userDefaults.object(forKey: key) != nil {
                boolSection[key] = userDefaults.bool(forKey: key)
            }
        }
        backup["booleans"] = boolSection

        // Dates — store as ISO8601 strings
        let dateFormatter = ISO8601DateFormatter()
        var dateSection: [String: String] = [:]
        for key in dateKeys {
            if let date = userDefaults.object(forKey: key) as? Date {
                dateSection[key] = dateFormatter.string(from: date)
            }
        }
        backup["dates"] = dateSection

        // String-Int dictionaries
        var dictSection: [String: [String: Int]] = [:]
        for key in stringIntDictKeys {
            if let dict = userDefaults.dictionary(forKey: key) as? [String: Int] {
                dictSection[key] = dict
            }
        }
        backup["dictionaries"] = dictSection

        let jsonData = try JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted, .sortedKeys])
        return jsonData
    }

    // MARK: - Import

    func importBackup(from data: Data) throws {
        guard let backup = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.invalidFormat
        }

        guard backup["backup_version"] as? Int == 1 else {
            throw BackupError.unsupportedVersion
        }

        // Snapshot all managed keys before writing anything. If any step below
        // throws, we restore the snapshot so the app is never left in a partial
        // state where referential integrity across stores is broken.
        let snapshot = captureSnapshot()
        do {
            try performImport(backup: backup)
        } catch {
            restoreSnapshot(snapshot)
            throw error
        }

        // All singleton stores cache state in memory at init time, so after a
        // successful import they must be told to re-read from UserDefaults.
        // Without this the running UI keeps showing pre-import data until the
        // user force-quits the app — and we must never quit programmatically
        // (App Review Guideline: apps cannot exit themselves).
        reloadAllStoresFromDisk()
    }

    /// Order matters only loosely — each reload posts its own change
    /// notification, and observer VCs are idempotent. Categories and machines
    /// reload first since templates reference them.
    private func reloadAllStoresFromDisk() {
        CategoryStore.shared.reloadFromDisk()
        MachineStore.shared.reloadFromDisk()
        ExerciseStore.shared.reloadFromDisk()
        WorkoutLibraryStore.shared.reloadFromDisk()
        ScheduleStore.shared.reloadFromDisk()
        CompletionStore.shared.reloadFromDisk()
        WeightLogStore.shared.reloadFromDisk()
        WorkoutSnapshotStore.shared.reloadFromDisk()
        UserProfileStore.shared.reloadFromDisk()
        StreakStore.shared.reloadFromDisk()
    }

    private var allManagedKeys: [String] {
        jsonDataKeys + stringArrayKeys + stringKeys + integerKeys + boolKeys + dateKeys + stringIntDictKeys
    }

    private func captureSnapshot() -> [String: Any] {
        var snapshot: [String: Any] = [:]
        for key in allManagedKeys {
            if let value = userDefaults.object(forKey: key) {
                snapshot[key] = value
            }
        }
        return snapshot
    }

    private func restoreSnapshot(_ snapshot: [String: Any]) {
        for key in allManagedKeys {
            if let value = snapshot[key] {
                userDefaults.set(value, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }
    }

    private func performImport(backup: [String: Any]) throws {
        // JSON Data keys
        if let section = backup["json_data"] as? [String: String] {
            for (key, base64) in section {
                guard jsonDataKeys.contains(key) else { continue }
                if let decoded = Data(base64Encoded: base64) {
                    userDefaults.set(decoded, forKey: key)
                }
            }
        }

        // String arrays
        if let section = backup["string_arrays"] as? [String: [String]] {
            for (key, array) in section {
                guard stringArrayKeys.contains(key) else { continue }
                userDefaults.set(array, forKey: key)
            }
        }

        // Strings
        if let section = backup["strings"] as? [String: String] {
            for (key, value) in section {
                guard stringKeys.contains(key) else { continue }
                userDefaults.set(value, forKey: key)
            }
        }

        // Integers
        if let section = backup["integers"] as? [String: Int] {
            for (key, value) in section {
                guard integerKeys.contains(key) else { continue }
                userDefaults.set(value, forKey: key)
            }
        }

        // Booleans
        if let section = backup["booleans"] as? [String: Bool] {
            for (key, value) in section {
                guard boolKeys.contains(key) else { continue }
                userDefaults.set(value, forKey: key)
            }
        }

        // Dates
        let dateFormatter = ISO8601DateFormatter()
        if let section = backup["dates"] as? [String: String] {
            for (key, dateString) in section {
                guard dateKeys.contains(key) else { continue }
                if let date = dateFormatter.date(from: dateString) {
                    userDefaults.set(date, forKey: key)
                }
            }
        }

        // String-Int dictionaries
        if let section = backup["dictionaries"] as? [String: [String: Int]] {
            for (key, dict) in section {
                guard stringIntDictKeys.contains(key) else { continue }
                userDefaults.set(dict, forKey: key)
            }
        }
    }

    enum BackupError: LocalizedError {
        case invalidFormat
        case unsupportedVersion

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "The backup file is not a valid Wacky Lifts backup."
            case .unsupportedVersion:
                return "This backup was created by a newer version of the app."
            }
        }
    }
}
