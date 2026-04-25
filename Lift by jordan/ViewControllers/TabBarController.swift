import UIKit

final class TabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureAppearance()
        viewControllers = [
            makeScheduleTab(),
            makeWorkoutsTab(),
            makeStreaksTab(),
            makeSettingsTab(),
        ]
    }

    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.6)

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = .secondaryLabel
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.secondaryLabel
        ]
        itemAppearance.selected.iconColor = .label
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = .label
    }

    private func configureNavigationAppearance(for navigationController: UINavigationController) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]

        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance
        navigationController.navigationBar.tintColor = .label
        navigationController.navigationBar.isTranslucent = true
    }

    private func makeScheduleTab() -> UIViewController {
        let vc = ScheduleViewController()
        let nav = UINavigationController(rootViewController: vc)
        configureNavigationAppearance(for: nav)
        nav.tabBarItem = UITabBarItem(
            title: "Schedule",
            image: UIImage(systemName: "calendar"),
            selectedImage: UIImage(systemName: "calendar.fill")
        )
        return nav
    }

    private func makeWorkoutsTab() -> UIViewController {
        let vc = WorkoutsViewController()
        let nav = UINavigationController(rootViewController: vc)
        configureNavigationAppearance(for: nav)
        nav.tabBarItem = UITabBarItem(
            title: "Workouts",
            image: UIImage(systemName: "figure.strengthtraining.traditional"),
            selectedImage: UIImage(systemName: "figure.strengthtraining.traditional")
        )
        return nav
    }

    private func makeStreaksTab() -> UIViewController {
        let vc = StreaksViewController()
        let nav = UINavigationController(rootViewController: vc)
        configureNavigationAppearance(for: nav)
        nav.tabBarItem = UITabBarItem(
            title: "Streaks",
            image: UIImage(systemName: "flame"),
            selectedImage: UIImage(systemName: "flame.fill")
        )
        return nav
    }

    private func makeSettingsTab() -> UIViewController {
        let vc = SettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        configureNavigationAppearance(for: nav)
        nav.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )
        return nav
    }
}
