import UIKit

final class WorkoutsViewController: UIViewController {
    private var tableView: UITableView!
    private var dataSource:
        UITableViewDiffableDataSource<WorkoutTemplate.Category, WorkoutTemplate>!

    private let categorized = WorkoutLibrary.categorized
    private let categories = WorkoutLibrary.categories

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Workouts"
        view.backgroundColor = .clear
        applyLiquidGlassBackground()

        configureTableView()
        configureDataSource()
        applySnapshot()
    }

    private func configureTableView() {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorEffect = UIVibrancyEffect(
            blurEffect: UIBlurEffect(style: .systemUltraThinMaterial))
        tableView.sectionHeaderTopPadding = 12
        tableView.delegate = self
        view.addSubview(tableView)
        self.tableView = tableView

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<WorkoutTemplate.Category, WorkoutTemplate>(
            tableView: tableView
        ) { tableView, indexPath, workout in
            let cell =
                tableView.dequeueReusableCell(withIdentifier: WorkoutCell.reuseIdentifier)
                as? WorkoutCell
                ?? WorkoutCell(style: .subtitle, reuseIdentifier: WorkoutCell.reuseIdentifier)

            var content = UIListContentConfiguration.subtitleCell()
            content.text = workout.name
            content.secondaryText = "\(workout.exercises.count) exercises"
            content.image = UIImage(systemName: "figure.strengthtraining.traditional")
            content.imageProperties.tintColor = UIColor.systemBlue
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            cell.contentConfiguration = content

            cell.accessoryType = .disclosureIndicator
            cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
            cell.backgroundConfiguration?.backgroundColor = UIColor.secondarySystemBackground
                .withAlphaComponent(0.7)
            return cell
        }

        tableView.register(WorkoutCell.self, forCellReuseIdentifier: WorkoutCell.reuseIdentifier)
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<WorkoutTemplate.Category, WorkoutTemplate>()
        snapshot.appendSections(categories)
        for category in categories {
            let items = categorized[category, default: []]
            snapshot.appendItems(items, toSection: category)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension WorkoutsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let workout = dataSource.itemIdentifier(for: indexPath) else { return }
        tableView.deselectRow(at: indexPath, animated: true)

        let detailVC = WorkoutDetailViewController(workout: workout)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let category = dataSource.sectionIdentifier(for: section) else { return nil }
        return category.rawValue
    }
}

// MARK: - Detail

private final class WorkoutDetailViewController: UIViewController {
    private let workout: WorkoutTemplate
    private let textView = UITextView()

    init(workout: WorkoutTemplate) {
        self.workout = workout
        super.init(nibName: nil, bundle: nil)
        title = workout.name
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        applyLiquidGlassBackground()
        configureTextView()
    }

    private func configureTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.font = .preferredFont(forTextStyle: .body)
        textView.text = detailText()
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func detailText() -> String {
        let header = "\(workout.category.rawValue)\n\n"
        let exercises = workout.exercises.map { exercise in
            "\(exercise.name) – \(exercise.sets) sets (\(exercise.reps) reps)"
        }.joined(separator: "\n")
        return header + exercises
    }
}

// MARK: - UI

private final class WorkoutCell: UITableViewCell {
    static let reuseIdentifier = "WorkoutCell"
}
