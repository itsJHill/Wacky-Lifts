import UIKit

protocol ProgramEditorViewControllerDelegate: AnyObject {
    func programEditorDidSave(_ controller: ProgramEditorViewController)
}

final class ProgramEditorViewController: UIViewController {

    enum Mode {
        case create
        case edit(Program)

        var title: String {
            switch self {
            case .create: return "New Program"
            case .edit: return "Edit Program"
            }
        }
    }

    weak var delegate: ProgramEditorViewControllerDelegate?

    private let store = ProgramStore.shared
    private let libraryStore = WorkoutLibraryStore.shared
    private let mode: Mode

    private var draftId: UUID
    private var draftName: String
    private var draftWeeks: [ProgramWeek]
    private var draftColorHex: String
    private var isActiveProgram: Bool

    private var draftColor: UIColor { UIColor(hex: draftColorHex) ?? .systemIndigo }

    private var tableView: UITableView!

    private enum Section: Int, CaseIterable {
        case name, color, weeks, addWeek, actions
    }

    // Track which week-day is expanded for editing
    private var editingDay: (weekIndex: Int, weekday: Weekday)?

    // MARK: - Init

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            self.draftId = UUID()
            self.draftName = ""
            self.draftWeeks = []
            self.draftColorHex = "#5856D6"
            self.isActiveProgram = false
        case .edit(let program):
            self.draftId = program.id
            self.draftName = program.name
            self.draftWeeks = program.weeks
            self.draftColorHex = program.colorHex
            self.isActiveProgram = ProgramStore.shared.activeProgramId == program.id
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = mode.title

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped)
        )

        configureTableView()
        observeLibraryChanges()
    }

    private func observeLibraryChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryChange),
            name: WorkoutLibraryStore.libraryDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleLibraryChange() {
        tableView.reloadData()
    }

    // MARK: - TableView

    private func configureTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NameCell")
        tableView.register(ProgramColorCell.self, forCellReuseIdentifier: "ColorCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        guard !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showAlert(title: "Name Required", message: "Please enter a program name.")
            return
        }

        let program = Program(id: draftId, name: draftName, weeks: draftWeeks, colorHex: draftColorHex)
        switch mode {
        case .create:
            store.add(program)
        case .edit:
            if isActiveProgram {
                // Only keep completed and current weeks, replace future weeks
                let currentWeek = store.currentWeekNumber() ?? 0
                var frozenWeeks = draftWeeks.filter { $0.weekNumber <= currentWeek }
                let futureWeeks = draftWeeks.filter { $0.weekNumber > currentWeek }
                frozenWeeks = Array(frozenWeeks.prefix(currentWeek + 1))
                let finalProgram = Program(id: draftId, name: draftName, weeks: frozenWeeks + futureWeeks, colorHex: draftColorHex)
                store.update(finalProgram)
            } else {
                store.update(program)
            }
        }

        delegate?.programEditorDidSave(self)
        dismiss(animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func buildColorPicker(in container: UIView) {
        container.subviews.forEach { $0.removeFromSuperview() }

        let colors = Program.presetColors

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        for color in colors {
            let circle = UIView()
            circle.backgroundColor = UIColor(hex: color.hex)
            circle.layer.cornerRadius = 18
            circle.layer.borderWidth = draftColorHex == color.hex ? 3 : 0
            circle.layer.borderColor = UIColor.white.cgColor
            circle.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                circle.widthAnchor.constraint(equalToConstant: 36),
                circle.heightAnchor.constraint(equalToConstant: 36),
            ])

            let tap = UITapGestureRecognizer(target: self, action: #selector(colorTapped(_:)))
            circle.addGestureRecognizer(tap)
            circle.accessibilityLabel = color.name
            circle.tag = hashColorTag(color.hex)

            stack.addArrangedSubview(circle)
        }
    }

    private func hashColorTag(_ hex: String) -> Int {
        var hasher = Hasher()
        hasher.combine(hex)
        return abs(hasher.finalize())
    }

    @objc private func colorTapped(_ gesture: UITapGestureRecognizer) {
        guard let circle = gesture.view else { return }
        let colors = Program.presetColors
        for color in colors {
            if circle.tag == hashColorTag(color.hex) {
                draftColorHex = color.hex
                HapticManager.shared.light()
                tableView.reloadData()
                break
            }
        }
    }

    // MARK: - Week Management

    private func addWeek() {
        let nextNumber = (draftWeeks.last?.weekNumber ?? 0) + 1
        let week = ProgramWeek(weekNumber: nextNumber, days: [])
        draftWeeks.append(week)
        tableView.reloadData()
    }

    private func removeWeek(at index: Int) {
        guard index >= 0, index < draftWeeks.count else { return }
        draftWeeks.remove(at: index)
        // Re-number weeks
        for i in index..<draftWeeks.count {
            draftWeeks[i] = ProgramWeek(weekNumber: i + 1, days: draftWeeks[i].days)
        }
        tableView.reloadData()
    }

    private func addDay(weekIndex: Int) {
        guard weekIndex >= 0, weekIndex < draftWeeks.count else { return }
        showWeekdayPicker { [weak self] weekday in
            guard let self = self else { return }
            var week = self.draftWeeks[weekIndex]
            // Don't add duplicate days
            guard !week.days.contains(where: { $0.weekday == weekday }) else { return }
            let day = ProgramDay(weekday: weekday, workoutIds: [])
            week.days.append(day)
            week.days.sort { $0.weekday < $1.weekday }
            self.draftWeeks[weekIndex] = week
            self.tableView.reloadData()
        }
    }

    private func showWeekdayPicker(completion: @escaping (Weekday) -> Void) {
        let alert = UIAlertController(title: "Add Day", message: nil, preferredStyle: .actionSheet)
        for day in Weekday.allCases {
            alert.addAction(UIAlertAction(title: day.fullSymbol, style: .default) { _ in
                completion(day)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func pickWorkouts(for weekIndex: Int, weekday: Weekday) {
        guard weekIndex >= 0, weekIndex < draftWeeks.count else { return }
        let week = draftWeeks[weekIndex]
        let currentIds = week.days.first(where: { $0.weekday == weekday })?.workoutIds ?? []
        let selectedWorkouts = currentIds.compactMap { libraryStore.template(withId: $0) }
        let availableWorkouts = libraryStore.templates

        let picker = WorkoutPickerViewController(
            allWorkouts: availableWorkouts,
            preselected: selectedWorkouts,
            allowsCreation: true
        )
        picker.delegate = self
        picker.dayContext = (weekIndex, weekday)
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ProgramEditorViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .name:
            return 1
        case .color:
            return 1
        case .weeks:
            return draftWeeks.count
        case .addWeek:
            return 1
        case .actions:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .name: return "Program Name"
        case .color: return "Program Color"
        case .weeks: return draftWeeks.isEmpty ? nil : "Weeks"
        case .addWeek: return nil
        case .actions: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let s = Section(rawValue: indexPath.section) else { return tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) }

        switch s {
        case .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: "NameCell", for: indexPath)
            var content = UIListContentConfiguration.cell()
            content.text = draftName.isEmpty ? "Untitled Program" : draftName
            content.secondaryText = "Tap to edit name"
            content.image = UIImage(systemName: "pencil")
            content.imageProperties.tintColor = .systemBlue
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .color:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ColorCell", for: indexPath)
            buildColorPicker(in: cell.contentView)
            return cell

        case .weeks:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            let week = draftWeeks[indexPath.row]

            let dayNames = week.days.map { $0.weekday.shortSymbol }.joined(separator: ", ")
            let totalWorkouts = week.days.flatMap { $0.workoutIds }.count

            var content = UIListContentConfiguration.subtitleCell()
            content.text = "Week \(week.weekNumber)"
            content.secondaryText = dayNames.isEmpty ? "No days added" : "\(totalWorkouts) workouts on \(dayNames)"
            content.image = UIImage(systemName: "calendar.badge.clock")
            content.imageProperties.tintColor = draftColor
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .addWeek:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = UIListContentConfiguration.cell()
            content.text = "Add Week"
            content.image = UIImage(systemName: "plus.circle.fill")
            content.imageProperties.tintColor = .systemGreen
            cell.contentConfiguration = content
            return cell

        case .actions:
            return tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        }
    }
}

// MARK: - UITableViewDelegate

extension ProgramEditorViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let s = Section(rawValue: indexPath.section) else { return }

        switch s {
        case .name:
            showNameEditor()
        case .color:
            break
        case .weeks:
            editWeek(at: indexPath.row)
        case .addWeek:
            addWeek()
        case .actions:
            break
        }
    }

    private func showNameEditor() {
        let alert = UIAlertController(title: "Program Name", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = self.draftName
            textField.placeholder = "e.g. 4-Week Strength Builder"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let text = alert.textFields?.first?.text else { return }
            self.draftName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private func editWeek(at index: Int) {
        guard index >= 0, index < draftWeeks.count else { return }
        let week = draftWeeks[index]
        let weekVC = ProgramWeekEditorViewController(week: week, weekIndex: index, isActiveProgram: isActiveProgram, programColor: draftColor)
        weekVC.delegate = self
        let nav = UINavigationController(rootViewController: weekVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .weeks else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.removeWeek(at: indexPath.row)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - ProgramWeekEditorViewControllerDelegate

extension ProgramEditorViewController: ProgramWeekEditorViewControllerDelegate {
    func programWeekEditor(_ controller: ProgramWeekEditorViewController, didUpdate week: ProgramWeek, at index: Int) {
        guard index >= 0, index < draftWeeks.count else { return }
        draftWeeks[index] = week
        tableView.reloadData()
    }
}

// MARK: - WorkoutPickerViewControllerDelegate

extension ProgramEditorViewController: WorkoutPickerViewControllerDelegate {
    func workoutPicker(_ controller: WorkoutPickerViewController, didSelectWorkouts workouts: [WorkoutTemplate]) {
        // Use the day context to update the correct week/day
        if let context = controller.dayContext {
            let (weekIndex, weekday) = context
            guard weekIndex >= 0, weekIndex < draftWeeks.count else { return }
            var week = draftWeeks[weekIndex]
            if let dayIndex = week.days.firstIndex(where: { $0.weekday == weekday }) {
                week.days[dayIndex] = ProgramDay(weekday: weekday, workoutIds: workouts.map { $0.id })
            } else {
                let day = ProgramDay(weekday: weekday, workoutIds: workouts.map { $0.id })
                week.days.append(day)
                week.days.sort { $0.weekday < $1.weekday }
            }
            draftWeeks[weekIndex] = week
        tableView.reloadData()
    }
}

private final class ProgramColorCell: UITableViewCell {
    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.subviews.forEach { $0.removeFromSuperview() }
    }
}
}

// MARK: - ProgramWeekEditorViewController

protocol ProgramWeekEditorViewControllerDelegate: AnyObject {
    func programWeekEditor(_ controller: ProgramWeekEditorViewController, didUpdate week: ProgramWeek, at index: Int)
}

final class ProgramWeekEditorViewController: UIViewController {

    weak var delegate: ProgramWeekEditorViewControllerDelegate?

    private let week: ProgramWeek
    private let weekIndex: Int
    private let isActiveProgram: Bool
    private var draftDays: [ProgramDay]
    private var draftNotes: String
    private let programColor: UIColor

    private let libraryStore = WorkoutLibraryStore.shared

    private var tableView: UITableView!

    private enum Section: Int, CaseIterable {
        case notes, days
    }

    init(week: ProgramWeek, weekIndex: Int, isActiveProgram: Bool, programColor: UIColor) {
        self.week = week
        self.weekIndex = weekIndex
        self.isActiveProgram = isActiveProgram
        self.draftDays = week.days.sorted { $0.weekday < $1.weekday }
        self.draftNotes = week.notes
        self.programColor = programColor
        super.init(nibName: nil, bundle: nil)
        title = "Week \(week.weekNumber)"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Add Day", style: .plain, target: self, action: #selector(addDayTapped)
        )

        configureTableView()
    }

    @objc private func cancelTapped() {
        let updatedWeek = ProgramWeek(weekNumber: week.weekNumber, days: draftDays, notes: draftNotes)
        delegate?.programWeekEditor(self, didUpdate: updatedWeek, at: weekIndex)
        dismiss(animated: true)
    }

    @objc private func addDayTapped() {
        let alert = UIAlertController(title: "Add Day", message: nil, preferredStyle: .actionSheet)
        let existingWeekdays = Set(draftDays.map { $0.weekday })
        for day in Weekday.allCases where !existingWeekdays.contains(day) {
            alert.addAction(UIAlertAction(title: day.fullSymbol, style: .default) { [weak self] _ in
                guard let self = self else { return }
                let newDay = ProgramDay(weekday: day, workoutIds: [])
                self.draftDays.append(newDay)
                self.draftDays.sort { $0.weekday < $1.weekday }
                self.tableView.reloadData()
            })
        }
        if existingWeekdays.count == Weekday.allCases.count {
            alert.message = "All days already added"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func configureTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DayCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func pickWorkouts(for day: ProgramDay) {
        let currentIds = day.workoutIds
        let selectedWorkouts = currentIds.compactMap { libraryStore.template(withId: $0) }
        let availableWorkouts = libraryStore.templates

        let picker = WorkoutPickerViewController(
            allWorkouts: availableWorkouts,
            preselected: selectedWorkouts,
            allowsCreation: true
        )
        picker.delegate = self
        picker.dayContext = (weekIndex, day.weekday)
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
}

extension ProgramWeekEditorViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .notes: return 1
        case .days: return draftDays.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .notes: return "Phase Notes"
        case .days: return draftDays.isEmpty ? nil : "Days"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let s = Section(rawValue: indexPath.section) else {
            return tableView.dequeueReusableCell(withIdentifier: "DayCell", for: indexPath)
        }

        switch s {
        case .notes:
            let cell = tableView.dequeueReusableCell(withIdentifier: "DayCell", for: indexPath)
            var content = UIListContentConfiguration.subtitleCell()
            content.text = draftNotes.isEmpty ? "Add progression notes..." : draftNotes
            content.secondaryText = draftNotes.isEmpty ? "e.g. Add 5 lbs this week, 0-1 RIR" : "Tap to edit"
            content.image = UIImage(systemName: "pencil.and.list.clipboard")
            content.imageProperties.tintColor = programColor
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            content.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .days:
            let cell = tableView.dequeueReusableCell(withIdentifier: "DayCell", for: indexPath)
            let day = draftDays[indexPath.row]

            var content = UIListContentConfiguration.subtitleCell()
            content.text = day.weekday.fullSymbol
            let resolved = day.workoutIds.compactMap { libraryStore.template(withId: $0) }.map { $0.name }
            content.secondaryText = resolved.isEmpty ? "No workouts" : resolved.joined(separator: ", ")
            content.image = UIImage(systemName: "dumbbell.fill")
            content.imageProperties.tintColor = programColor
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            content.secondaryTextProperties.numberOfLines = 2
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
}

extension ProgramWeekEditorViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let s = Section(rawValue: indexPath.section) else { return }
        switch s {
        case .notes:
            showNotesEditor()
        case .days:
            let day = draftDays[indexPath.row]
            pickWorkouts(for: day)
        }
    }

    private func showNotesEditor() {
        let alert = UIAlertController(title: "Phase Notes", message: "Reminders for this week's progression.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = self.draftNotes
            textField.placeholder = "e.g. Add 5 lbs, 0-1 RIR on last set"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let text = alert.textFields?.first?.text else { return }
            self.draftNotes = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .days else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, completion in
            self?.draftDays.remove(at: indexPath.row)
            self?.tableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

extension ProgramWeekEditorViewController: WorkoutPickerViewControllerDelegate {
    func workoutPicker(_ controller: WorkoutPickerViewController, didSelectWorkouts workouts: [WorkoutTemplate]) {
        guard let context = controller.dayContext else { return }
        let (_, weekday) = context
        if let index = draftDays.firstIndex(where: { $0.weekday == weekday }) {
            draftDays[index] = ProgramDay(weekday: weekday, workoutIds: workouts.map { $0.id })
        }
        tableView.reloadData()
    }
}
