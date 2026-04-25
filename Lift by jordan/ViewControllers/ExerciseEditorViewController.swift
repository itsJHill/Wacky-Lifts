import UIKit

protocol ExerciseEditorViewControllerDelegate: AnyObject {
    func exerciseEditorDidSave(_ controller: ExerciseEditorViewController, exercise: ExerciseDefinition)
    func exerciseEditorDidDelete(_ controller: ExerciseEditorViewController, exerciseId: UUID)
}

final class ExerciseEditorViewController: UIViewController {

    enum Mode {
        case create
        case edit(ExerciseDefinition)
    }

    weak var delegate: ExerciseEditorViewControllerDelegate?

    private let mode: Mode
    private let exerciseStore = ExerciseStore.shared
    private let machineStore = MachineStore.shared

    private var draftId: UUID
    private var draftName: String
    private var draftMachineId: UUID?

    private var tableView: UITableView!

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            draftId = UUID()
            draftName = ""
            draftMachineId = nil
        case .edit(let exercise):
            draftId = exercise.id
            draftName = exercise.name
            draftMachineId = exercise.machineId
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        switch mode {
        case .create: title = "New Exercise"
        case .edit: title = "Edit Exercise"
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark.circle.fill"),
            style: .prominent, target: self, action: #selector(saveTapped))

        configureTableView()
    }

    // MARK: - Table View

    private func configureTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
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
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let alert = UIAlertController(title: "Name Required",
                                          message: "Enter a name for this exercise.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let exercise = ExerciseDefinition(id: draftId, name: trimmed, machineId: draftMachineId)

        switch mode {
        case .create:
            exerciseStore.add(exercise)
        case .edit:
            exerciseStore.update(exercise)
        }

        delegate?.exerciseEditorDidSave(self, exercise: exercise)
        dismiss(animated: true)
    }

    private func promptForName() {
        let alert = UIAlertController(title: "Exercise Name", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.text = self?.draftName
            textField.placeholder = "e.g., Bench Press"
            textField.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            guard let self, let text = alert.textFields?.first?.text else { return }
            self.draftName = text
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private func promptForMachine() {
        let machines = machineStore.machines
        let alert = UIAlertController(title: "Select Machine", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "None (Free Weight / Bodyweight)", style: .default) { [weak self] _ in
            self?.draftMachineId = nil
            self?.tableView.reloadData()
        })

        for machine in machines {
            let checkmark = (machine.id == draftMachineId) ? " ✓" : ""
            alert.addAction(UIAlertAction(title: "\(machine.name)\(checkmark)", style: .default) { [weak self] _ in
                self?.draftMachineId = machine.id
                self?.tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func confirmDelete() {
        let usedIn = exerciseStore.workoutsUsing(exerciseId: draftId)
        let message: String
        if usedIn.isEmpty {
            message = "Are you sure you want to delete this exercise?"
        } else {
            let names = usedIn.map(\.name).joined(separator: ", ")
            message = "This exercise is used in: \(names). Deleting it will remove it from those workouts."
        }

        let alert = UIAlertController(title: "Delete Exercise", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            // Remove from workouts
            for template in usedIn {
                let updated = WorkoutTemplate(
                    id: template.id,
                    name: template.name,
                    categoryId: template.categoryId,
                    exercises: template.exercises.filter { $0.exerciseId != self.draftId },
                    iconName: template.iconName
                )
                WorkoutLibraryStore.shared.update(updated)
            }
            self.exerciseStore.delete(id: self.draftId)
            self.delegate?.exerciseEditorDidDelete(self, exerciseId: self.draftId)
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension ExerciseEditorViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        switch mode {
        case .create: return 1
        case .edit: return 2
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 2 }  // Name, Machine
        return 1  // Delete
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
            cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground

            if indexPath.row == 0 {
                cell.textLabel?.text = "Name"
                cell.detailTextLabel?.text = draftName.isEmpty ? "Tap to set" : draftName
                cell.detailTextLabel?.textColor = draftName.isEmpty ? .tertiaryLabel : .label
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Machine"
                if let machineId = draftMachineId,
                   let machine = machineStore.machine(for: machineId) {
                    cell.detailTextLabel?.text = machine.name
                } else {
                    cell.detailTextLabel?.text = "None"
                }
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.accessoryType = .disclosureIndicator
            }
            return cell
        } else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Delete Exercise"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.textAlignment = .center
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
            cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                promptForName()
            } else {
                promptForMachine()
            }
        } else {
            confirmDelete()
        }
    }
}
