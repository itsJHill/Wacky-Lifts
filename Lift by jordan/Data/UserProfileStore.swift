import Foundation

final class UserProfileStore {
    static let shared = UserProfileStore()

    static let nameDidChangeNotification = Notification.Name("UserProfileStore.nameDidChange")

    private let userDefaults = UserDefaults.standard
    private let nameKey = "user_display_name"

    var displayName: String? {
        didSet {
            if let name = displayName, !name.isEmpty {
                userDefaults.set(name, forKey: nameKey)
            } else {
                displayName = nil
                userDefaults.removeObject(forKey: nameKey)
            }
            NotificationCenter.default.post(name: Self.nameDidChangeNotification, object: self)
        }
    }

    private init() {
        displayName = userDefaults.string(forKey: nameKey)
    }

    func reset() {
        displayName = nil
    }

    /// Re-read the stored display name from UserDefaults. The `displayName`
    /// didSet handles both persistence and the change notification. Called by
    /// `DataBackupManager` after import.
    func reloadFromDisk() {
        displayName = userDefaults.string(forKey: nameKey)
    }
}
