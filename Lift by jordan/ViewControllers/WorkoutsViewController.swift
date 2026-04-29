@preconcurrency import UIKit

final class WorkoutsViewController: UIViewController {
    private let store = WorkoutLibraryStore.shared
    private let exerciseStore = ExerciseStore.shared
    private let weightLogStore = WeightLogStore.shared

    // MARK: - Segmented Control

    private lazy var segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Workouts", "Plans", "Exercises"])
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return sc
    }()

    private lazy var programListVC: ProgramListViewController = {
        let vc = ProgramListViewController()
        vc.delegate = self
        return vc
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

    private lazy var exerciseSearchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.placeholder = "Search exercises"
        bar.searchBarStyle = .minimal
        bar.delegate = self
        return bar
    }()

    private var isSearchingExercises = false

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

    private lazy var searchExercisesButton: UIBarButtonItem = {
        let btn = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(searchExercisesTapped)
        )
        btn.accessibilityLabel = "Search exercises"
        return btn
    }()

    private lazy var actionsToggleButton: UIBarButtonItem = {
        let btn = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(actionsToggleTapped)
        )
        btn.accessibilityLabel = "Show actions"
        return btn
    }()

    /// Whether the Exercises-segment right-hand actions (search + add) are
    /// currently expanded. Collapsed shows just the ellipsis toggle to save
    /// horizontal room for the centered segmented control.
    private var isActionsExpanded = false

    private lazy var cancelSearchButton: UIBarButtonItem = {
        UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelSearchTapped)
        )
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.titleView = segmentedControl

        definesPresentationContext = true

        configureWorkoutsTableView()
        configureWorkoutsDataSource()
        configureProgramsView()
        configureExercisesTableView()
        configureExercisesDataSource()

        updateNavBarForSegment()
        applyWorkoutsSnapshot()
        applyExercisesSnapshot()
        observeChanges()
    }

    private func configureProgramsView() {
        addChild(programListVC)
        programListVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(programListVC.view)
        programListVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            programListVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            programListVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            programListVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            programListVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        programListVC.view.isHidden = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Segment Switching

    @objc private func segmentChanged() {
        let showWorkouts = segmentedControl.selectedSegmentIndex == 0
        let showPlans = segmentedControl.selectedSegmentIndex == 1
        workoutsTableView.isHidden = !showWorkouts
        programListVC.view.isHidden = !showPlans
        exercisesTableView.isHidden = !(segmentedControl.selectedSegmentIndex == 2)
        updateNavBarForSegment()
    }

    private func updateNavBarForSegment() {
        let showingWorkouts = segmentedControl.selectedSegmentIndex == 0
        let showingPlans = segmentedControl.selectedSegmentIndex == 1
        // If the user was searching and switched back to Workouts, tear
        // down the search UI cleanly.
        if (showingWorkouts || showingPlans) && isSearchingExercises {
            exitSearchMode(clearText: true, refreshList: false)
        }
        navigationItem.leftBarButtonItem = nil

        let segmentActions: [UIBarButtonItem]
        if showingWorkouts {
            segmentActions = [addWorkoutButton, categoriesButton]
        } else if showingPlans {
            let addPlanButton = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(addProgramTapped)
            )
            addPlanButton.accessibilityLabel = "Add program"
            segmentActions = [addPlanButton]
        } else {
            segmentActions = [addExerciseButton, searchExercisesButton]
        }

        if isActionsExpanded {
            navigationItem.rightBarButtonItems = [actionsToggleButton] + segmentActions
        } else {
            navigationItem.rightBarButtonItems = [actionsToggleButton]
        }
    }

    @objc private func actionsToggleTapped() {
        isActionsExpanded.toggle()
        actionsToggleButton.image = UIImage(
            systemName: isActionsExpanded ? "chevron.right" : "chevron.left"
        )
        actionsToggleButton.accessibilityLabel = isActionsExpanded
            ? "Hide actions"
            : "Show actions"
        let showingWorkouts = segmentedControl.selectedSegmentIndex == 0
        let showingPlans = segmentedControl.selectedSegmentIndex == 1
        let segmentActions: [UIBarButtonItem]
        if showingWorkouts {
            segmentActions = [addWorkoutButton, categoriesButton]
        } else if showingPlans {
            let addPlanButton = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(addProgramTapped)
            )
            addPlanButton.accessibilityLabel = "Add program"
            segmentActions = [addPlanButton]
        } else {
            segmentActions = [addExerciseButton, searchExercisesButton]
        }
        let items: [UIBarButtonItem] = isActionsExpanded
            ? [actionsToggleButton] + segmentActions
            : [actionsToggleButton]
        navigationItem.setRightBarButtonItems(items, animated: true)
    }

    // MARK: - Search Mode

    @objc private func searchExercisesTapped() {
        enterSearchMode()
    }

    @objc private func cancelSearchTapped() {
        exitSearchMode(clearText: true, refreshList: true)
    }

    private func enterSearchMode() {
        guard !isSearchingExercises else { return }
        isSearchingExercises = true
        navigationItem.titleView = exerciseSearchBar
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItems = [cancelSearchButton]
        exerciseSearchBar.becomeFirstResponder()
    }

    private func exitSearchMode(clearText: Bool, refreshList: Bool) {
        guard isSearchingExercises else { return }
        isSearchingExercises = false
        if clearText { exerciseSearchBar.text = "" }
        exerciseSearchBar.resignFirstResponder()
        navigationItem.titleView = segmentedControl
        // Keep the actions group expanded so the user lands back on the
        // [search, add, collapse] layout they started from — tapping the
        // chevron is still available if they want to tidy it up.
        isActionsExpanded = true
        actionsToggleButton.image = UIImage(systemName: "chevron.right")
        actionsToggleButton.accessibilityLabel = "Hide actions"
        // Restore the segment-appropriate bar buttons (the Cancel button was
        // only meant to live during search mode).
        updateNavBarForSegment()
        // Caller decides whether to re-apply the snapshot so filter clears.
        if refreshList { applyExercisesSnapshot() }
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

    @objc private func addProgramTapped() {
        let editor = ProgramEditorViewController(mode: .create)
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
                let display = self?.weightLogStore.displayWeight(pr.weight, for: exercise.id, unit: pr.unit)
                    ?? "\(Self.formatWeight(pr.weight)) \(pr.unit.symbol)"
                details.append("PR: \(display)")
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
        let searchText = exerciseSearchBar.text ?? ""
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

// MARK: - UISearchBarDelegate

extension WorkoutsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyExercisesSnapshot()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
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

// MARK: - ProgramListViewControllerDelegate

extension WorkoutsViewController: ProgramListViewControllerDelegate {
    func programListDidRequestCreate(_ controller: ProgramListViewController) {
        addProgramTapped()
    }

    func programList(_ controller: ProgramListViewController, didSelect program: Program) {
        let detailVC = ProgramDetailViewController(program: program, startDate: ProgramStore.shared.activeStartDate)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func programList(_ controller: ProgramListViewController, didSelectCompleted completion: ProgramCompletion) {
        let detailVC = ProgramDetailViewController(completion: completion)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func programList(_ controller: ProgramListViewController, didRequestEdit program: Program) {
        let editor = ProgramEditorViewController(mode: .edit(program))
        editor.delegate = self
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
}

// MARK: - ProgramEditorViewControllerDelegate

extension WorkoutsViewController: ProgramEditorViewControllerDelegate {
    func programEditorDidSave(_ controller: ProgramEditorViewController) {
        // ProgramListVC auto-reloads via notification
    }
}
