import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .systemBackground
        window.rootViewController = TabBarController()

        // Apply saved theme preference
        ThemeManager.shared.applyTheme(to: window)

        window.makeKeyAndVisible()
        self.window = window

        promptForNameIfNeeded()
    }

    private func promptForNameIfNeeded() {
        let profile = UserProfileStore.shared
        guard profile.displayName == nil, !profile.hasBeenPrompted else { return }
        profile.hasBeenPrompted = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let rootVC = self?.window?.rootViewController else { return }

            let alert = UIAlertController(
                title: "What's Your Name?",
                message: "Personalize your experience with a greeting.",
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.placeholder = "Enter your name"
                textField.autocapitalizationType = .words
                textField.returnKeyType = .done
            }
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let name, !name.isEmpty {
                    profile.displayName = name
                }
            })
            alert.addAction(UIAlertAction(title: "Skip", style: .cancel))
            rootVC.present(alert, animated: true)
        }
    }
}
