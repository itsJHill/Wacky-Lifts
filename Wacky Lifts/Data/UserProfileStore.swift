import Foundation

final class UserProfileStore {
    static let shared = UserProfileStore()

    static let nameDidChangeNotification = Notification.Name("UserProfileStore.nameDidChange")

    private let userDefaults = UserDefaults.standard
    private let nameKey = "user_display_name"
    private let promptShownKey = "user_name_prompt_shown"

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

    var hasBeenPrompted: Bool {
        didSet {
            userDefaults.set(hasBeenPrompted, forKey: promptShownKey)
        }
    }

    private init() {
        displayName = userDefaults.string(forKey: nameKey)
        hasBeenPrompted = userDefaults.bool(forKey: promptShownKey)
    }

    func reset() {
        displayName = nil
        hasBeenPrompted = false
    }
}
