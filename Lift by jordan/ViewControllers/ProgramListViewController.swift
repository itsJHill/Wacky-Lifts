import UIKit

protocol ProgramListViewControllerDelegate: AnyObject {
    func programListDidRequestCreate(_ controller: ProgramListViewController)
    func programList(_ controller: ProgramListViewController, didSelect program: Program)
    func programList(_ controller: ProgramListViewController, didSelectCompleted completion: ProgramCompletion)
    func programList(_ controller: ProgramListViewController, didRequestEdit program: Program)
}

final class ProgramListViewController: UIViewController {

    weak var delegate: ProgramListViewControllerDelegate?

    private let store = ProgramStore.shared
    private let scheduleStore = ScheduleStore.shared

    private var tableView: UITableView!
    private enum Section: Int, CaseIterable {
        case active, saved, past
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureTableView()
        observeChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Observations

    private func observeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProgramsChange),
            name: ProgramStore.programsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProgramsChange),
            name: ProgramStore.activeProgramDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleProgramsChange() {
        tableView.reloadData()
    }

    // MARK: - TableView

    private func configureTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProgramCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - UITableViewDataSource

extension ProgramListViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .active:
            return store.hasActiveProgram ? 1 : 0
        case .saved:
            return store.programs.count
        case .past:
            return min(store.completedPrograms.count, 1) // collapsed by default, show count in footer
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .active:
            return store.hasActiveProgram ? "Active Program" : nil
        case .saved:
            return store.programs.isEmpty ? nil : "Programs"
        case .past:
            return store.completedPrograms.isEmpty ? nil : "Past Programs"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProgramCell", for: indexPath)

        guard let s = Section(rawValue: indexPath.section) else { return cell }

        switch s {
        case .active:
            guard let program = store.activeProgram,
                  let startDate = store.activeStartDate else { break }
            let weekNum = store.currentWeekNumber()
            let currentWeek = (weekNum ?? -1) + 1

            var content = UIListContentConfiguration.subtitleCell()
            content.text = program.name
            let weekText = currentWeek > 0 ? "Week \(currentWeek) of \(program.weeks.count)" : "Started"
            content.secondaryText = "\(weekText) — Started \(Self.displayFormatter.string(from: startDate))"
            content.image = UIImage(systemName: "flame.fill")
            content.imageProperties.tintColor = program.color
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator

        case .saved:
            let program = store.programs[indexPath.row]
            let isActive = store.activeProgramId == program.id

            var content = UIListContentConfiguration.subtitleCell()
            content.text = program.name
            content.secondaryText = "\(program.weeks.count) weeks"
            if isActive {
                content.secondaryText = "Active • " + (content.secondaryText ?? "")
            }
            content.image = UIImage(systemName: "calendar")
            content.imageProperties.tintColor = program.color
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator

        case .past:
            let completed = store.completedPrograms[indexPath.row]
            var content = UIListContentConfiguration.subtitleCell()
            content.text = completed.programName
            content.secondaryText = "\(Self.displayFormatter.string(from: completed.startDate)) – \(Self.displayFormatter.string(from: completed.endDate))"
            content.image = UIImage(systemName: "checkmark.seal.fill")
            content.imageProperties.tintColor = .systemGray
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
        }

        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ProgramListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let s = Section(rawValue: indexPath.section) else { return }

        switch s {
        case .active:
            guard let program = store.activeProgram else { return }
            delegate?.programList(self, didSelect: program)

        case .saved:
            let program = store.programs[indexPath.row]
            delegate?.programList(self, didSelect: program)

        case .past:
            let completed = store.completedPrograms[indexPath.row]
            delegate?.programList(self, didSelectCompleted: completed)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let s = Section(rawValue: indexPath.section) else { return nil }

        switch s {
        case .active:
            let deactivate = UIContextualAction(style: .destructive, title: "End") { [weak self] _, _, completion in
                guard let self = self else { return }
                let alert = UIAlertController(
                    title: "End Program",
                    message: "Are you sure you want to end this program? Your completed workouts will be preserved.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "End", style: .destructive) { _ in
                    self.store.deactivate(completedAllWeeks: false)
                })
                self.present(alert, animated: true)
                completion(true)
            }
            deactivate.image = UIImage(systemName: "stop.circle")
            return UISwipeActionsConfiguration(actions: [deactivate])

        case .saved:
            let program = store.programs[indexPath.row]

            var actions: [UIContextualAction] = []

            let activate = UIContextualAction(style: .normal, title: "Start") { [weak self] _, _, completion in
                guard let self = self else { return }
                self.showStartDatePicker(for: program)
                completion(true)
            }
            activate.backgroundColor = .systemGreen
            activate.image = UIImage(systemName: "play.circle")
            actions.append(activate)

            let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, completion in
                guard let self = self else { completion(true); return }
                self.delegate?.programList(self, didRequestEdit: program)
                completion(true)
            }
            edit.backgroundColor = .systemBlue
            edit.image = UIImage(systemName: "pencil")
            actions.append(edit)

            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                self?.confirmDeleteProgram(program)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            actions.append(delete)

            return UISwipeActionsConfiguration(actions: actions)

        case .past:
            return nil
        }
    }

    // MARK: - Actions

    private func showStartDatePicker(for program: Program) {
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
            let startDate = AppDateCoding.startOfDay(for: datePicker.date)
            self?.store.activate(programId: program.id, startDate: startDate)
        })
        present(alert, animated: true)
    }

    private func confirmDeleteProgram(_ program: Program) {
        let alert = UIAlertController(
            title: "Delete Program",
            message: "Delete \"\(program.name)\"? This won't affect completed workouts.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.store.delete(id: program.id)
        })
        present(alert, animated: true)
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
