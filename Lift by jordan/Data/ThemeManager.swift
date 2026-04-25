import UIKit

enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var description: String {
        switch self {
        case .system: return "Follows your device settings"
        case .light: return "Always use light appearance"
        case .dark: return "Always use dark appearance"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class ThemeManager {
    static let shared = ThemeManager()

    static let themeDidChangeNotification = Notification.Name("ThemeManager.themeDidChange")

    private let userDefaults = UserDefaults.standard
    private let themeKey = "app_theme"

    var currentTheme: AppTheme {
        didSet {
            userDefaults.set(currentTheme.rawValue, forKey: themeKey)
            applyTheme()
            NotificationCenter.default.post(name: Self.themeDidChangeNotification, object: self)
        }
    }

    private init() {
        let savedValue = userDefaults.integer(forKey: themeKey)
        currentTheme = AppTheme(rawValue: savedValue) ?? .system
    }

    func applyTheme() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        for window in windowScene.windows {
            window.overrideUserInterfaceStyle = currentTheme.userInterfaceStyle
        }
    }

    func applyTheme(to window: UIWindow) {
        window.overrideUserInterfaceStyle = currentTheme.userInterfaceStyle
    }
}
