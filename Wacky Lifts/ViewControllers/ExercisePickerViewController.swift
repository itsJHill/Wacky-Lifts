import UIKit

protocol ExercisePickerViewControllerDelegate: AnyObject {
    func exercisePicker(_ controller: ExercisePickerViewController,
                        didSelect exercises: [ExerciseDefinition])
}

final class ExercisePickerViewController: UIViewController {

    weak var delegate: ExercisePickerViewControllerDelegate?

    private let exerciseStore = ExerciseStore.shared
    private var allExercises: [ExerciseDefinition] = []
    private var filteredExercises: [ExerciseDefinition] = []
    private var selectedIds: Set<UUID> = []

    /// Exercise IDs already in the workout (shown but not selectable)
    private let existingExerciseIds: Set<UUID>

    private var tableView: UITableView!
    private let searchController = UISearchController(searchResultsController: nil)

    init(existingExerciseIds: Set<UUID> = []) {
        self.existingExerciseIds = existingExerciseIds
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Add Exercises"
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done", style: .prominent, target: self, action: #selector(doneTapped))
        updateDoneButton()

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search exercises"
        navigationItem.searchController = searchController
        definesPresentationContext = true

        configureTableView()
        reloadExercises()
    }

    private func configureTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func reloadExercises() {
        allExercises = exerciseStore.sortedByName()
        applyFilter()
    }

    private func applyFilter() {
        let searchText = searchController.searchBar.text ?? ""
        if searchText.isEmpty {
            filteredExercises = allExercises
        } else {
            filteredExercises = allExercises.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        tableView.reloadData()
    }

    private func updateDoneButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !selectedIds.isEmpty
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        let selected = allExercises.filter { selectedIds.contains($0.id) }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.exercisePicker(self, didSelect: selected)
        }
    }
}

// MARK: - UITableViewDataSource & Delegate

extension ExercisePickerViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        2 // "Create New" + exercise list
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : filteredExercises.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Create New Exercise"
            cell.textLabel?.textColor = .systemBlue
            cell.imageView?.image = UIImage(systemName: "plus.circle.fill")
            cell.imageView?.tintColor = .systemBlue
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
            cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
            return cell
        }

        let exercise = filteredExercises[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)

        cell.textLabel?.text = exercise.name
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)

        if let machineId = exercise.machineId,
           let machine = MachineStore.shared.machine(for: machineId) {
            cell.detailTextLabel?.text = machine.name
            cell.detailTextLabel?.textColor = .secondaryLabel
        }

        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground

        if existingExerciseIds.contains(exercise.id) {
            cell.accessoryType = .checkmark
            cell.textLabel?.textColor = .tertiaryLabel
            cell.isUserInteractionEnabled = false
        } else if selectedIds.contains(exercise.id) {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            promptCreateExercise()
            return
        }

        let exercise = filteredExercises[indexPath.row]
        guard !existingExerciseIds.contains(exercise.id) else { return }

        if selectedIds.contains(exercise.id) {
            selectedIds.remove(exercise.id)
        } else {
            selectedIds.insert(exercise.id)
        }

        tableView.reloadRows(at: [indexPath], with: .none)
        updateDoneButton()
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "Exercise Library" : nil
    }

    // MARK: - Create New

    private func promptCreateExercise() {
        let alert = UIAlertController(title: "New Exercise", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Exercise name"
            textField.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self, let name = alert.textFields?.first?.text,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let exercise = ExerciseDefinition(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            self.exerciseStore.add(exercise)
            self.selectedIds.insert(exercise.id)
            self.reloadExercises()
            self.updateDoneButton()
        })
        present(alert, animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension ExercisePickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }
}
