@preconcurrency import UIKit

final class CategoriesViewController: UIViewController {
    private let store = CategoryStore.shared
    private var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Categories"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        configureNavBar()
        configureTableView()
        observeCategoryChanges()
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
        closeButton.accessibilityHint = "Dismisses the categories screen"
        navigationItem.leftBarButtonItem = closeButton

        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addCategoryTapped)
        )
        addButton.accessibilityLabel = "Add category"
        addButton.accessibilityHint = "Creates a new category"
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func observeCategoryChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCategoryChange),
            name: CategoryStore.categoriesDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleCategoryChange() {
        tableView.reloadData()
    }

    @objc private func addCategoryTapped() {
        promptForCategoryName(existingName: nil) { [weak self] newName in
            self?.store.add(name: newName)
        }
    }

    private func promptForCategoryName(existingName: String?, completion: @escaping (String) -> Void) {
        let isEditing = existingName != nil
        let alert = UIAlertController(
            title: isEditing ? "Edit Category" : "New Category",
            message: nil,
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "Category name"
            field.text = existingName
            field.autocapitalizationType = .words
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: isEditing ? "Save" : "Add", style: .default) { _ in
                let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { return }
                completion(name)
            }
        )

        present(alert, animated: true)
    }

    private func confirmDelete(category: WorkoutCategory) {
        let workoutsToDelete = WorkoutLibraryStore.shared.templates.filter { $0.categoryId == category.id }
        let workoutCount = workoutsToDelete.count

        var message = "This will permanently remove the \"\(category.name)\" category."
        if workoutCount > 0 {
            message += " \(workoutCount) workout\(workoutCount == 1 ? "" : "s") in this category will also be deleted."
        }

        let alert = UIAlertController(
            title: "Delete Category",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                // Delete all workouts in this category first
                for workout in workoutsToDelete {
                    WorkoutLibraryStore.shared.delete(id: workout.id)
                }
                // Then delete the category
                self?.store.delete(id: category.id)
            }
        )

        present(alert, animated: true)
    }
}

extension CategoriesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.sortedCategories.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
        let category = store.sortedCategories[indexPath.row]

        var content = UIListContentConfiguration.cell()
        content.text = category.name
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        cell.contentConfiguration = content

        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = store.sortedCategories[indexPath.row]

        promptForCategoryName(existingName: category.name) { [weak self] newName in
            self?.store.update(id: category.id, name: newName)
        }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        store.move(fromIndex: sourceIndexPath.row, toIndex: destinationIndexPath.row)
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .delete
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let category = store.sortedCategories[indexPath.row]
        confirmDelete(category: category)
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Tap the red button to delete. Drag to reorder. Tap to rename."
    }
}
