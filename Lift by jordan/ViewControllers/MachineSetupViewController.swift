@preconcurrency import UIKit

final class MachineSetupViewController: UIViewController, MachineEditorViewControllerDelegate {
    private let store = MachineStore.shared
    private var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Machine Setup"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        configureNavBar()
        configureTableView()
        observeChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureNavBar() {
        let closeButton = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        closeButton.accessibilityLabel = "Close"
        closeButton.accessibilityHint = "Dismisses the machine setup screen"
        navigationItem.leftBarButtonItem = closeButton

        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addMachineTapped)
        )
        addButton.accessibilityLabel = "Add machine"
        addButton.accessibilityHint = "Creates a new machine"
        navigationItem.rightBarButtonItem = addButton
    }

    private func configureTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MachineCell")

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func observeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMachineChange),
            name: MachineStore.machinesDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleMachineChange() {
        tableView.reloadData()
    }

    @objc private func addMachineTapped() {
        let editor = MachineEditorViewController()
        editor.delegate = self
        navigationController?.pushViewController(editor, animated: true)
    }

    private func promptForBodyweightMachine(
        existing: WeightMachine,
        completion: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(
            title: "Edit Machine",
            message: "Bodyweight exercises have no weight increments.",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "Machine name"
            field.text = existing.name
            field.autocapitalizationType = .words
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Save", style: .default) { _ in
                let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { return }
                completion(name)
            }
        )

        present(alert, animated: true)
    }

    private func confirmDelete(machine: WeightMachine) {
        let alert = UIAlertController(
            title: "Delete Machine",
            message: "This will permanently remove \"\(machine.name)\". Exercises using this machine will fall back to standard increments.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                self?.store.delete(id: machine.id)
            }
        )

        present(alert, animated: true)
    }

    // MARK: - MachineEditorViewControllerDelegate

    func machineEditorDidSave(_ controller: MachineEditorViewController) {
        // Table reloads via notification
    }
}

extension MachineSetupViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.sortedMachines.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MachineCell", for: indexPath)
        let machine = store.sortedMachines[indexPath.row]

        var content = UIListContentConfiguration.subtitleCell()
        content.text = machine.name
        content.secondaryText = machine.displayDescription
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content

        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let machine = store.sortedMachines[indexPath.row]

        if machine.isBodyweight {
            promptForBodyweightMachine(existing: machine) { [weak self] name in
                self?.store.update(id: machine.id, name: name, weights: [])
            }
        } else {
            let editor = MachineEditorViewController(machine: machine)
            editor.delegate = self
            navigationController?.pushViewController(editor, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        store.move(fromIndex: sourceIndexPath.row, toIndex: destinationIndexPath.row)
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        let machine = store.sortedMachines[indexPath.row]
        return machine.isBodyweight ? .none : .delete
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let machine = store.sortedMachines[indexPath.row]
        confirmDelete(machine: machine)
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Tap the red button to delete. Drag to reorder. Tap to edit weight positions.\n\nEach machine stores exact weight positions. The +/- buttons step through them in order."
    }
}
