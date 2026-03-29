import UIKit

final class ResetDataViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let streakStore = StreakStore.shared

    private enum ResetOption: Int, CaseIterable {
        case streak
        case everything

        var title: String {
            switch self {
            case .streak: return "Streak"
            case .everything: return "Everything"
            }
        }

        var subtitle: String {
            switch self {
            case .streak: return "Resets current and longest streak to 0"
            case .everything: return "Clears schedule, history, weight logs, and streaks"
            }
        }

        var icon: UIImage? {
            switch self {
            case .streak: return UIImage(systemName: "flame.fill")
            case .everything: return UIImage(systemName: "trash.fill")
            }
        }
    }

    private var options = ResetOption.allCases

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Reset Data"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .clear
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

extension ResetDataViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let option = options[indexPath.row]

        var content = UIListContentConfiguration.subtitleCell()
        content.text = option.title
        content.secondaryText = option.subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = option.icon
        content.imageProperties.tintColor = .systemRed
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Swipe to reset"
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let option = options[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "Reset") {
            [weak self] _, _, completion in
            self?.performReset(option)
            completion(true)
        }
        action.image = UIImage(systemName: "trash")
        let config = UISwipeActionsConfiguration(actions: [action])
        config.performsFirstActionWithFullSwipe = false
        return config
    }

    private func performReset(_ option: ResetOption) {
        switch option {
        case .streak:
            streakStore.resetStreakOnly()
        case .everything:
            ScheduleStore.shared.resetAll()
            CompletionStore.shared.resetAll()
            WeightLogStore.shared.resetAll()
            WorkoutSnapshotStore.shared.resetAll()
            ExerciseStore.shared.resetAll()
            streakStore.resetAllStats()
            UserProfileStore.shared.reset()
        }
    }
}
