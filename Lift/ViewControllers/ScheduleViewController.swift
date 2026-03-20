import UIKit

final class ScheduleViewController: UIViewController {

    private enum Section {
        case main
    }

    private let store = ScheduleStore.shared
    private let isoCalendar = Calendar(identifier: .iso8601)

    private var days: [WeekdayStripView.Day] = []
    private var weekdays: [Weekday] = Weekday.allCases
    private var selectedWeekday: Weekday = .monday

    private let headerLabel: UILabel = {
        let label = UILabel()
        label.text = "This Week"
        label.font = .preferredFont(forTextStyle: .title2)
        label.textColor = .label
        return label
    }()

    private let weekStripView = WeekdayStripView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var dataSource: UITableViewDiffableDataSource<Section, WorkoutTemplate>!

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No workouts yet.\nTap + to add workouts."
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Schedule"
        view.backgroundColor = .clear
        applyLiquidGlassBackground()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addWorkoutTapped)
        )

        configureDays()
        configureLayout()
        configureWeekStrip()
        configureTableView()
        configureDataSource()
        applySnapshot(animated: false)
        observeScheduleChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureDays() {
        let today = Date()
        let startOfWeek = isoCalendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = isoCalendar
        dayFormatter.dateFormat = "EEE"

        let numberFormatter = DateFormatter()
        numberFormatter.calendar = isoCalendar
        numberFormatter.dateFormat = "d"

        var computedDays: [WeekdayStripView.Day] = []
        for offset in 0..<7 {
            guard let date = isoCalendar.date(byAdding: .day, value: offset, to: startOfWeek) else {
                continue
            }
            let symbol = dayFormatter.string(from: date)
            let shortLabel = numberFormatter.string(from: date)
            computedDays.append(.init(date: date, symbol: symbol, shortLabel: shortLabel))
        }
        days = computedDays

        let isoWeekday = isoCalendar.component(.weekday, from: today)
        selectedWeekday = weekdayFromISO(isoWeekday)
    }

    private func configureLayout() {
        let headerStack = UIStackView(arrangedSubviews: [headerLabel, weekStripView])
        headerStack.axis = .vertical
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            weekStripView.heightAnchor.constraint(equalToConstant: 72),

            tableView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureWeekStrip() {
        weekStripView.configure(days: days, selectedIndex: indexForWeekday(selectedWeekday))
        weekStripView.onSelectionChanged = { [weak self] selection in
            guard let self else { return }
            let index = selection.index
            guard index >= 0, index < self.weekdays.count else { return }
            self.selectedWeekday = self.weekdays[index]
            self.applySnapshot(animated: true)
        }
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorEffect = UIVibrancyEffect(
            blurEffect: UIBlurEffect(style: .systemUltraThinMaterial))
        tableView.sectionHeaderTopPadding = 12
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "WorkoutCell")
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, WorkoutTemplate>(
            tableView: tableView
        ) { tableView, indexPath, workout in
            let cell = tableView.dequeueReusableCell(withIdentifier: "WorkoutCell", for: indexPath)
            var content = UIListContentConfiguration.subtitleCell()
            content.text = workout.name
            content.secondaryText = workout.category.rawValue
            content.image = UIImage(systemName: "figure.strengthtraining.traditional")
            content.imageProperties.tintColor = .systemBlue
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
            cell.backgroundConfiguration?.backgroundColor = UIColor.secondarySystemBackground
                .withAlphaComponent(0.65)
            return cell
        }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, WorkoutTemplate>()
        snapshot.appendSections([.main])
        let workouts = store.workouts(for: selectedWeekday)
        snapshot.appendItems(workouts, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animated)

        tableView.backgroundView = workouts.isEmpty ? emptyStateLabel : nil
    }

    private func observeScheduleChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScheduleChange),
            name: ScheduleStore.scheduleDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleScheduleChange() {
        applySnapshot(animated: true)
    }

    @objc private func addWorkoutTapped() {
        let selectedWorkouts = store.workouts(for: selectedWeekday)
        let picker = WorkoutPickerViewController(
            allWorkouts: store.availableWorkouts,
            preselected: selectedWorkouts
        )
        picker.delegate = self
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func weekdayFromISO(_ isoWeekday: Int) -> Weekday {
        switch isoWeekday {
        case 1: return .monday
        case 2: return .tuesday
        case 3: return .wednesday
        case 4: return .thursday
        case 5: return .friday
        case 6: return .saturday
        default: return .sunday
        }
    }

    private func indexForWeekday(_ weekday: Weekday) -> Int {
        Weekday.allCases.firstIndex(of: weekday) ?? 0
    }
}

extension ScheduleViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let workout = dataSource.itemIdentifier(for: indexPath) else { return }
        tableView.deselectRow(at: indexPath, animated: true)

        let detailVC = WorkoutDetailViewController(workout: workout)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        selectedWeekday.fullSymbol
    }

    func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let workout = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Remove") {
            [weak self] _, _, completion in
            self?.store.remove(templateId: workout.id, from: self?.selectedWeekday ?? .monday)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

extension ScheduleViewController: WorkoutPickerViewControllerDelegate {
    func workoutPicker(
        _ controller: WorkoutPickerViewController, didSelectWorkouts workouts: [WorkoutTemplate]
    ) {
        store.replace(day: selectedWeekday, with: workouts)
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
