import UIKit

final class AllPRsViewController: UIViewController {

    private let weightLogStore = WeightLogStore.shared
    private var tableView: UITableView!
    private var prs: [ExerciseLog] = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Personal Records"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped))

        configureTableView()
        loadPRs()
    }

    private func configureTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PRCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func loadPRs() {
        prs = weightLogStore.allPersonalRecords()
        tableView.reloadData()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

extension AllPRsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        prs.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PRCell", for: indexPath)
        let pr = prs[indexPath.row]

        var content = UIListContentConfiguration.subtitleCell()
        content.text = pr.exerciseName

        let weightText = pr.weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", pr.weight)
            : String(format: "%.1f", pr.weight)
        content.secondaryText = "\(weightText) \(pr.unit.symbol) • \(Self.dateFormatter.string(from: pr.date))"

        content.image = UIImage(systemName: "trophy.fill")
        content.imageProperties.tintColor = .systemYellow
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        content.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        prs.isEmpty ? nil : "\(prs.count) Personal Records"
    }
}
