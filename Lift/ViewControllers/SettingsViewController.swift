import UIKit

final class SettingsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Section: Int, CaseIterable {
        case appearance
        case about

        var title: String {
            switch self {
            case .appearance: return "Appearance"
            case .about: return "About"
            }
        }
    }

    private enum Row: Hashable {
        case useSystemTheme
        case appVersion
        case privacyNote
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Row>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .clear
        applyLiquidGlassBackground()
        configureTableView()
        configureDataSource()
        applySnapshot()
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Row>(tableView: tableView) {
            [weak self] tableView, indexPath, row in
            guard let self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.selectionStyle = .none
            cell.accessoryView = nil
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)

            switch row {
            case .useSystemTheme:
                cell.textLabel?.text = "Use System Appearance"
                let toggle = UISwitch()
                toggle.isOn = true
                toggle.isEnabled = false
                cell.accessoryView = toggle
            case .appVersion:
                cell.textLabel?.text = "Version"
                cell.accessoryType = .none
                cell.detailTextLabel?.text =
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                cell.contentConfiguration = UIListContentConfiguration.valueCell().updated(
                    for: cell.state
                ).with {
                    var config = $0
                    config.text = "Version"
                    config.secondaryText =
                        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                        ?? "1.0"
                    return config
                }
            case .privacyNote:
                cell.textLabel?.text = "Data is stored only on this device."
                cell.textLabel?.textColor = .secondaryLabel
                cell.textLabel?.numberOfLines = 0
            }

            cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
            cell.backgroundConfiguration?.backgroundColor = UIColor.secondarySystemBackground
                .withAlphaComponent(0.65)

            return cell
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([.useSystemTheme], toSection: .appearance)
        snapshot.appendItems([.appVersion, .privacyNote], toSection: .about)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension UIListContentConfiguration {
    fileprivate func with(_ transform: (inout UIListContentConfiguration) -> Void)
        -> UIListContentConfiguration
    {
        var copy = self
        transform(&copy)
        return copy
    }
}
