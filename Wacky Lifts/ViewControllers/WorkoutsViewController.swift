@preconcurrency import UIKit

final class WorkoutsViewController: UIViewController {
    private let store = WorkoutLibraryStore.shared
    private let exerciseStore = ExerciseStore.shared
    private let weightLogStore = WeightLogStore.shared

    // MARK: - Segmented Control

    private lazy var segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Workouts", "Exercises"])
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return sc
    }()

    // MARK: - Workouts Pane

    private var workoutsTableView: UITableView!
    private nonisolated(unsafe) var workoutsDataSource:
        UITableViewDiffableDataSource<UUID, WorkoutTemplate>!

    private var categorized: [UUID: [WorkoutTemplate]] { store.categorized }
    private var categoryIds: [UUID] { store.categoryIds }

    // MARK: - Exercises Pane

    private var exercisesTableView: UITableView!
    private nonisolated(unsafe) var exercisesDataSource:
        UITableViewDiffableDataSource<String, ExerciseDefinition>!

    private lazy var exerciseSearchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = "Search exercises"
        return sc
    }()

    // MARK: - Nav Bar Items

    private lazy var categoriesButton: UIBarButtonItem = {
        let btn = UIBarButtonItem(
            image: UIImage(systemName: "folder.badge.gearshape"),
            style: .plain,
            target: self,
            action: #selector(manageCategoriesTapped)
        )
        btn.accessibilityLabel = "Manage categories"
        return btn
    }()

    private lazy var addWorkoutButton: UIBarButtonItem = {
        let btn = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addWorkoutTapped)
        )
        btn.accessibilityLabel = "Add workout"
        return btn
    }()

    private lazy var addExerciseButton: UIBarButtonItem = {
        let btn = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addExerciseTapped)
        )
        btn.accessibilityLabel = "Add exercise"
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.titleView = segmentedControl

        definesPresentationContext = true
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.preferredSearchBarPlacement = .integrated

        configureWorkoutsTableView()
        configureWorkoutsDataSource()
        configureExercisesTableView()
        configureExercisesDataSource()

        updateNavBarForSegment()
        applyWorkoutsSnapshot()
        applyExercisesSnapshot()
        observeChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Segment Switching

    @objc private func segmentChanged() {
        let showWorkouts = segmentedControl.selectedSegmentIndex == 0
        workoutsTableView.isHidden = !showWorkouts
        exercisesTableView.isHidden = showWorkouts
        updateNavBarForSegment()
    }

    private func updateNavBarForSegment() {
        let showingWorkouts = segmentedControl.selectedSegmentIndex == 0
        if showingWorkouts {
            navigationItem.leftBarButtonItem = categoriesButton
            navigationItem.rightBarButtonItem = addWorkoutButton
            exerciseSearchController.isActive = false
            navigationItem.searchController = nil
        } else {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = addExerciseButton
            navigationItem.searchController = exerciseSearchController
        }
    }

    // MARK: - Observations

    private func observeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkoutsChange),
            name: WorkoutLibraryStore.libraryDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkoutsChange),
            name: CategoryStore.categoriesDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExercisesChange),
            name: ExerciseStore.exercisesDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExercisesChange),
            name: WeightLogStore.logsDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleWorkoutsChange() {
        applyWorkoutsSnapshot()
    }

    @objc private func handleExercisesChange() {
        applyExercisesSnapshot()
    }

    // MARK: - Actions

    @objc private func manageCategoriesTapped() {
        let categoriesVC = CategoriesViewController()
        let nav = UINavigationController(rootViewController: categoriesVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    @objc private func addWorkoutTapped() {
        let editor = WorkoutEditorViewController(mode: .create)
        editor.delegate = self
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    @objc private func addExerciseTapped() {
        let editor = ExerciseEditorViewController(mode: .create)
        editor.delegate = self
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    // MARK: - Workouts Table View

    private func configureWorkoutsTableView() {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorEffect = UIVibrancyEffect(
            blurEffect: UIBlurEffect(style: .systemUltraThinMaterial))
        tv.sectionHeaderTopPadding = 12
        tv.delegate = self
        tv.tag = 0
        view.addSubview(tv)
        workoutsTableView = tv

        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tv.topAnchor.constraint(equalTo: view.topAnchor),
            tv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureWorkoutsDataSource() {
        workoutsTableView.register(WorkoutCell.self, forCellReuseIdentifier: WorkoutCell.reuseIdentifier)
        workoutsDataSource = UITableViewDiffableDataSource<UUID, WorkoutTemplate>(
            tableView: workoutsTableView
        ) { (tableView, indexPath, workout) in
            let cell =
                tableView.dequeueReusableCell(withIdentifier: WorkoutCell.reuseIdentifier)
                as? WorkoutCell
                ?? WorkoutCell(style: .subtitle, reuseIdentifier: WorkoutCell.reuseIdentifier)

            var content = UIListContentConfiguration.subtitleCell()
            content.text = workout.name
            content.secondaryText = "\(workout.exercises.count) exercises"
            let iconName = workout.iconName ?? "figure.strengthtraining.traditional"
            content.image = UIImage(systemName: iconName)
            content.imageProperties.tintColor = .systemBlue
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            cell.contentConfiguration = content

            cell.accessoryType = .disclosureIndicator
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
            cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
            return cell
        }
    }

    private func applyWorkoutsSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<UUID, WorkoutTemplate>()
        let activeCategories = categoryIds.filter { categorized[$0] != nil }
        snapshot.appendSections(activeCategories)
        for categoryId in activeCategories {
            let items = categorized[categoryId, default: []]
            snapshot.appendItems(items, toSection: categoryId)
        }
        workoutsDataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Exercises Table View

    private func configureExercisesTableView() {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorEffect = UIVibrancyEffect(
            blurEffect: UIBlurEffect(style: .systemUltraThinMaterial))
        tv.sectionHeaderTopPadding = 12
        tv.delegate = self
        tv.tag = 1
        tv.isHidden = true
        view.addSubview(tv)
        exercisesTableView = tv

        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tv.topAnchor.constraint(equalTo: view.topAnchor),
            tv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureExercisesDataSource() {
        exercisesTableView.register(ExerciseCell.self, forCellReuseIdentifier: ExerciseCell.reuseIdentifier)
        exercisesDataSource = UITableViewDiffableDataSource<String, ExerciseDefinition>(
            tableView: exercisesTableView
        ) { [weak self] (tableView, indexPath, exercise) in
            let cell =
                tableView.dequeueReusableCell(withIdentifier: ExerciseCell.reuseIdentifier)
                as? ExerciseCell
                ?? ExerciseCell(style: .subtitle, reuseIdentifier: ExerciseCell.reuseIdentifier)

            var content = UIListContentConfiguration.subtitleCell()
            content.text = exercise.name

            // Build subtitle: machine name + PR
            var details: [String] = []
            if let machineId = exercise.machineId,
               let machine = MachineStore.shared.machine(for: machineId) {
                details.append(machine.name)
            }
            if let pr = self?.weightLogStore.personalRecord(for: exercise.id) {
                details.append("PR: \(Self.formatWeight(pr.weight)) \(pr.unit.symbol)")
            }
            content.secondaryText = details.isEmpty ? nil : details.joined(separator: " • ")

            content.image = UIImage(systemName: "dumbbell")
            content.imageProperties.tintColor = .systemBlue
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            cell.contentConfiguration = content

            cell.accessoryType = .disclosureIndicator
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
            cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
            return cell
        }
    }

    private func applyExercisesSnapshot() {
        let searchText = exerciseSearchController.searchBar.text ?? ""
        var exercises = exerciseStore.sortedByName()
        if !searchText.isEmpty {
            exercises = exercises.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        var snapshot = NSDiffableDataSourceSnapshot<String, ExerciseDefinition>()
        snapshot.appendSections(["exercises"])
        snapshot.appendItems(exercises, toSection: "exercises")
        exercisesDataSource.apply(snapshot, animatingDifferences: false)
    }

    private static func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
    }
}

// MARK: - UITableViewDelegate

extension WorkoutsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if tableView.tag == 0 {
            // Workouts pane
            guard let workout = workoutsDataSource.itemIdentifier(for: indexPath) else { return }
            let editor = WorkoutEditorViewController(mode: .edit(workout))
            editor.delegate = self
            let nav = UINavigationController(rootViewController: editor)
            nav.modalPresentationStyle = .pageSheet
            present(nav, animated: true)
        } else {
            // Exercises pane
            guard let exercise = exercisesDataSource.itemIdentifier(for: indexPath) else { return }
            let editor = ExerciseEditorViewController(mode: .edit(exercise))
            editor.delegate = self
            let nav = UINavigationController(rootViewController: editor)
            nav.modalPresentationStyle = .pageSheet
            present(nav, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView.tag == 0 {
            guard let categoryId = workoutsDataSource.sectionIdentifier(for: section) else { return nil }
            let label = UILabel()
            label.text = CategoryStore.shared.category(for: categoryId)?.name ?? "Uncategorized"
            label.font = .preferredFont(forTextStyle: .headline)
            label.textColor = .secondaryLabel
            return label
        }
        return nil
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        if tableView.tag == 0 {
            guard let workout = workoutsDataSource.itemIdentifier(for: indexPath) else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") {
                [weak self] _, _, completion in
                self?.store.delete(id: workout.id)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [delete])
        } else {
            guard let exercise = exercisesDataSource.itemIdentifier(for: indexPath) else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") {
                [weak self] _, _, completion in
                self?.confirmDeleteExercise(exercise)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [delete])
        }
    }

    private func confirmDeleteExercise(_ exercise: ExerciseDefinition) {
        let usedIn = exerciseStore.workoutsUsing(exerciseId: exercise.id)
        let message: String
        if usedIn.isEmpty {
            message = "Are you sure you want to delete \"\(exercise.name)\"?"
        } else {
            let names = usedIn.map(\.name).joined(separator: ", ")
            message = "Deleting \"\(exercise.name)\" will remove it from these workouts: \(names). Continue?"
        }

        let alert = UIAlertController(title: "Delete Exercise", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            // Remove exercise entries from workouts that use it
            for template in usedIn {
                let updated = WorkoutTemplate(
                    id: template.id,
                    name: template.name,
                    categoryId: template.categoryId,
                    exercises: template.exercises.filter { $0.exerciseId != exercise.id },
                    iconName: template.iconName
                )
                WorkoutLibraryStore.shared.update(updated)
            }
            self?.exerciseStore.delete(id: exercise.id)
        })
        present(alert, animated: true)
    }
}

// MARK: - WorkoutEditorViewControllerDelegate

extension WorkoutsViewController: WorkoutEditorViewControllerDelegate {
    func workoutEditorDidSave(
        _ controller: WorkoutEditorViewController, workout: WorkoutTemplate
    ) {
        applyWorkoutsSnapshot()
    }

    func workoutEditorDidDelete(
        _ controller: WorkoutEditorViewController, workoutId: WorkoutTemplate.ID
    ) {
        applyWorkoutsSnapshot()
    }
}

// MARK: - ExerciseEditorViewControllerDelegate

extension WorkoutsViewController: ExerciseEditorViewControllerDelegate {
    func exerciseEditorDidSave(_ controller: ExerciseEditorViewController, exercise: ExerciseDefinition) {
        applyExercisesSnapshot()
    }

    func exerciseEditorDidDelete(_ controller: ExerciseEditorViewController, exerciseId: UUID) {
        applyExercisesSnapshot()
    }
}

// MARK: - UISearchResultsUpdating

extension WorkoutsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applyExercisesSnapshot()
    }
}

// MARK: - Cells

private final class WorkoutCell: UITableViewCell {
    static let reuseIdentifier = "WorkoutCell"
}

private final class ExerciseCell: UITableViewCell {
    static let reuseIdentifier = "ExerciseCell"
}

// MARK: - Detail (unused but retained)

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
        view.backgroundColor = .systemBackground
        configureTextView()
    }

    private func configureTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.backgroundColor = .systemBackground
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
        let header = "\(workout.categoryName)\n\n"
        let exercises = workout.exercises.map { exercise in
            "\(exercise.name) – \(exercise.detailSummary)"
        }.joined(separator: "\n")
        return header + exercises
    }
}
