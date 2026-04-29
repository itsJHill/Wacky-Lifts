import UIKit

final class ProgramDetailViewController: UIViewController {

    private let store = ProgramStore.shared
    private let completionStore = CompletionStore.shared
    private let libraryStore = WorkoutLibraryStore.shared
    private let weightLogStore = WeightLogStore.shared

    private var program: Program
    private let startDate: Date?
    private let completion: ProgramCompletion?
    private let isActive: Bool
    private let isPastProgram: Bool

    private var selectedWeekIndex: Int = 0

    private var weekSelector: UISegmentedControl!
    private var tableView: UITableView!

    // MARK: - Init

    init(program: Program, startDate: Date?) {
        self.program = program
        self.startDate = startDate
        self.completion = nil
        self.isActive = ProgramStore.shared.activeProgramId == program.id
        self.isPastProgram = false
        super.init(nibName: nil, bundle: nil)
        title = program.name
        if isActive, let start = startDate {
            let weekNum = ProgramStore.shared.currentWeekNumber() ?? 0
            selectedWeekIndex = max(0, min(weekNum, program.weeks.count - 1))
        }
    }

    init(completion: ProgramCompletion) {
        self.program = Program(id: completion.programId, name: completion.programName, weeks: [])
        self.startDate = completion.startDate
        self.completion = completion
        self.isActive = false
        self.isPastProgram = true
        super.init(nibName: nil, bundle: nil)
        title = completion.programName
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        configureWeekSelector()
        configureTableView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCompletionsChange),
            name: CompletionStore.completionsDidChangeNotification,
            object: nil
        )

        if !isActive && !program.weeks.isEmpty {
            let startButton = UIBarButtonItem(
                image: UIImage(systemName: "play.circle"),
                style: .plain,
                target: self,
                action: #selector(activateTapped)
            )
            let editButton = UIBarButtonItem(
                image: UIImage(systemName: "pencil"),
                style: .plain,
                target: self,
                action: #selector(editTapped)
            )
            navigationItem.rightBarButtonItems = isPastProgram ? nil : [startButton, editButton]
        }

        if isActive {
            let endButton = UIBarButtonItem(
                title: "End",
                style: .plain,
                target: self,
                action: #selector(endProgramTapped)
            )
            let editButton = UIBarButtonItem(
                image: UIImage(systemName: "pencil"),
                style: .plain,
                target: self,
                action: #selector(editTapped)
            )
            navigationItem.rightBarButtonItems = [editButton, endButton]
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @objc private func handleCompletionsChange() {
        tableView.reloadData()
    }

    @objc private func activateTapped() {
        activateProgram()
    }

    @objc private func editTapped() {
        let editor = ProgramEditorViewController(mode: .edit(program))
        editor.delegate = self
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func activateProgram() {
        let alert = UIAlertController(title: "Start \(program.name)", message: "\n\n\n\n\n\n\n\n\n", preferredStyle: .alert)

        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.date = Date()
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        alert.view.addSubview(datePicker)

        NSLayoutConstraint.activate([
            datePicker.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            datePicker.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 50),
        ])

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Start", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let startDate = AppDateCoding.startOfDay(for: datePicker.date)
            self.store.activate(programId: self.program.id, startDate: startDate)
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func endProgramTapped() {
        let alert = UIAlertController(
            title: "End Program",
            message: "Are you sure you want to end \"\(program.name)\"? Your completed workouts will be preserved.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "End", style: .destructive) { [weak self] _ in
            self?.store.deactivate(completedAllWeeks: false)
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - Week Selector

    private func configureWeekSelector() {
        let weekTitles = (0..<max(program.weeks.count, 1)).map { "W\($0 + 1)" }
        weekSelector = UISegmentedControl(items: weekTitles)
        weekSelector.translatesAutoresizingMaskIntoConstraints = false
        weekSelector.selectedSegmentIndex = selectedWeekIndex
        weekSelector.addTarget(self, action: #selector(weekChanged), for: .valueChanged)
        view.addSubview(weekSelector)

        if weekTitles.count <= 1 {
            weekSelector.isHidden = true
        }
    }

    @objc private func weekChanged() {
        selectedWeekIndex = weekSelector.selectedSegmentIndex
        tableView.reloadData()
    }

    // MARK: - TableView

    private func configureTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DayCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            weekSelector.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            weekSelector.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            weekSelector.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: weekSelector.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - UITableViewDataSource

extension ProgramDetailViewController: UITableViewDataSource {

    private enum Section: Int, CaseIterable {
        case notes, days
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        guard !program.weeks.isEmpty,
              selectedWeekIndex < program.weeks.count else { return 0 }
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section),
              !program.weeks.isEmpty,
              selectedWeekIndex < program.weeks.count else { return 0 }
        switch s {
        case .notes:
            return 1
        case .days:
            return program.weeks[selectedWeekIndex].days.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .notes: return "Week \(selectedWeekIndex + 1) Notes"
        case .days: return "Week \(selectedWeekIndex + 1) Plan"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let s = Section(rawValue: indexPath.section) else {
            return tableView.dequeueReusableCell(withIdentifier: "DayCell", for: indexPath)
        }

        switch s {
        case .notes:
            let cell = tableView.dequeueReusableCell(withIdentifier: "DayCell", for: indexPath)
            guard selectedWeekIndex < program.weeks.count else { return cell }
            let week = program.weeks[selectedWeekIndex]

            var content = UIListContentConfiguration.subtitleCell()
            if week.notes.isEmpty {
                content.text = "No notes for this week"
                content.textProperties.color = .secondaryLabel
            } else {
                content.text = week.notes
                content.textProperties.color = .label
            }
            content.image = UIImage(systemName: "pencil.and.list.clipboard")
            content.imageProperties.tintColor = program.color
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
            cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
            cell.selectionStyle = .none
            return cell

        case .days:
            let cell = tableView.dequeueReusableCell(withIdentifier: "DayCell", for: indexPath)
            guard selectedWeekIndex < program.weeks.count else { return cell }
            let week = program.weeks[selectedWeekIndex]
            guard indexPath.row < week.days.count else { return cell }
            let day = week.days[indexPath.row]

            let resolvedWorkouts = day.workoutIds.compactMap { libraryStore.template(withId: $0) }
            let workoutNames = resolvedWorkouts.map { $0.name }.joined(separator: ", ")

            // Determine completion
            var isComplete = false
            var completedCount = 0
            if let start = startDate {
                let calendar = AppDateCoding.calendar
                // Get Sunday of the program's start week
                guard let programStartWeek = AppDateCoding.startOfWeek(for: start) else { return cell }
                // Offset to the target week (week 1 = 0 days, week 2 = 7 days, etc.)
                let weekDaysOffset = (week.weekNumber - 1) * 7
                guard let targetWeekStart = calendar.date(byAdding: .day, value: weekDaysOffset, to: programStartWeek) else { return cell }
                // Offset to the specific weekday (Sunday = 0, Monday = 1, ..., Saturday = 6)
                let dayOffset = day.weekday.rawValue - 1
                guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: targetWeekStart) else { return cell }

                var allComplete = !resolvedWorkouts.isEmpty
                for workout in resolvedWorkouts {
                    if completionStore.isWorkoutFullyCompleted(workout, on: dayDate) {
                        completedCount += 1
                    } else {
                        allComplete = false
                    }
                }
                isComplete = resolvedWorkouts.isEmpty ? false : allComplete
            }

            var content = UIListContentConfiguration.subtitleCell()
            content.text = day.weekday.fullSymbol
            content.secondaryText = resolvedWorkouts.isEmpty ? "Rest day" : "\(workoutNames) • \(completedCount)/\(resolvedWorkouts.count) complete"
            content.image = UIImage(systemName: isComplete ? "checkmark.circle.fill" : "circle")
            content.imageProperties.tintColor = isComplete ? .systemGreen : .secondaryLabel
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            content.secondaryTextProperties.numberOfLines = 3
            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
            cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
            cell.selectionStyle = .none
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension ProgramDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - ProgramEditorViewControllerDelegate

extension ProgramDetailViewController: ProgramEditorViewControllerDelegate {
    func programEditorDidSave(_ controller: ProgramEditorViewController) {
        // Reload program from store
        if let updated = ProgramStore.shared.program(withId: program.id) {
            program = updated
            title = updated.name
        }
        // Rebuild week selector (weeks may have changed)
        weekSelector.removeFromSuperview()
        configureWeekSelector()
        // Rebuild week selector constraints
        if let parent = weekSelector.superview {
            NSLayoutConstraint.activate([
                weekSelector.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                weekSelector.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                weekSelector.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
        }
        tableView.reloadData()
    }
}
