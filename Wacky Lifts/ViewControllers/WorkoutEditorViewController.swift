@preconcurrency import UIKit

protocol WorkoutEditorViewControllerDelegate: AnyObject {
    func workoutEditorDidSave(_ controller: WorkoutEditorViewController, workout: WorkoutTemplate)
    func workoutEditorDidDelete(
        _ controller: WorkoutEditorViewController, workoutId: WorkoutTemplate.ID)
}

final class WorkoutEditorViewController: UIViewController, IconPickerViewControllerDelegate {
    private enum Section: Int, CaseIterable {
        case details
        case exercises
        case actions

        var title: String? {
            switch self {
            case .details: return "Details"
            case .exercises: return "Exercises"
            case .actions: return nil
            }
        }
    }

    enum Mode {
        case create
        case edit(WorkoutTemplate)

        var title: String {
            switch self {
            case .create: return "New Workout"
            case .edit: return "Edit Workout"
            }
        }
    }

    weak var delegate: WorkoutEditorViewControllerDelegate?

    private let store = WorkoutLibraryStore.shared
    private let weightLogStore = WeightLogStore.shared
    private let completionStore = CompletionStore.shared
    private let machineStore = MachineStore.shared
    private let mode: Mode

    private var draftId: WorkoutTemplate.ID
    private var draftName: String
    private var draftCategoryId: UUID
    private var draftExercises: [WorkoutTemplate.Exercise]
    private var draftIconName: String?
    private let iconOptions: [String] = [
        // Strength & Training
        "figure.strengthtraining.traditional",
        "dumbbell",
        "figure.strengthtraining.functional",
        "figure.core.training",
        "figure.cross.training",
        "figure.highintensity.intervaltraining",
        "figure.step.training",
        "figure.flexibility",
        "figure.cooldown",
        // Cardio
        "figure.run",
        "figure.run.treadmill",
        "figure.walk",
        "figure.walk.treadmill",
        "figure.hiking",
        "figure.elliptical",
        "figure.stair.stepper",
        "figure.stairs",
        "figure.indoor.cycle",
        "figure.outdoor.cycle",
        "figure.jumprope",
        "figure.mixed.cardio",
        "figure.track.and.field",
        // Water
        "figure.pool.swim",
        "figure.open.water.swim",
        "figure.water.fitness",
        // Combat & Martial Arts
        "figure.boxing",
        "figure.kickboxing",
        "figure.martial.arts",
        "figure.wrestling",
        "figure.fencing",
        // Mind & Body
        "figure.yoga",
        "figure.pilates",
        "figure.barre",
        "figure.taichi",
        "figure.mind.and.body",
        // Rowing
        "figure.indoor.rowing",
        "figure.outdoor.rowing",
        "figure.hand.cycling",
        // Generic
        "flame",
        "bolt.fill",
        "heart.fill",
        "trophy.fill",
    ]
    private let iconLabels: [String: String] = [
        "figure.strengthtraining.traditional": "Strength",
        "dumbbell": "Dumbbell",
        "figure.strengthtraining.functional": "Functional",
        "figure.core.training": "Core",
        "figure.cross.training": "Cross Train",
        "figure.highintensity.intervaltraining": "HIIT",
        "figure.step.training": "Step",
        "figure.flexibility": "Flexibility",
        "figure.cooldown": "Cooldown",
        "figure.run": "Run",
        "figure.run.treadmill": "Treadmill Run",
        "figure.walk": "Walk",
        "figure.walk.treadmill": "Treadmill Walk",
        "figure.hiking": "Hike",
        "figure.elliptical": "Elliptical",
        "figure.stair.stepper": "Stair Stepper",
        "figure.stairs": "Stairs",
        "figure.indoor.cycle": "Indoor Cycle",
        "figure.outdoor.cycle": "Outdoor Cycle",
        "figure.jumprope": "Jump Rope",
        "figure.mixed.cardio": "Mixed Cardio",
        "figure.track.and.field": "Track & Field",
        "figure.pool.swim": "Pool Swim",
        "figure.open.water.swim": "Open Water Swim",
        "figure.water.fitness": "Water Fitness",
        "figure.boxing": "Boxing",
        "figure.kickboxing": "Kickboxing",
        "figure.martial.arts": "Martial Arts",
        "figure.wrestling": "Wrestling",
        "figure.fencing": "Fencing",
        "figure.yoga": "Yoga",
        "figure.pilates": "Pilates",
        "figure.barre": "Barre",
        "figure.taichi": "Tai Chi",
        "figure.mind.and.body": "Mind & Body",
        "figure.indoor.rowing": "Indoor Row",
        "figure.outdoor.rowing": "Outdoor Row",
        "figure.hand.cycling": "Hand Cycle",
        "flame": "Burn",
        "bolt.fill": "Power",
        "heart.fill": "Cardio",
        "trophy.fill": "Trophy",
    ]

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            self.draftId = UUID()
            self.draftName = ""
            self.draftCategoryId = CategoryStore.shared.sortedCategories.first?.id ?? UUID()
            self.draftExercises = []
            self.draftIconName = "figure.strengthtraining.traditional"
        case .edit(let template):
            self.draftId = template.id
            self.draftName = template.name
            self.draftCategoryId = template.categoryId
            self.draftExercises = template.exercises
            self.draftIconName = template.iconName
        }
        super.init(nibName: nil, bundle: nil)
        self.title = mode.title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavBar()
        configureTableView()
    }

    private func configureNavBar() {
        navigationItem.largeTitleDisplayMode = .never

        let cancelButton = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        cancelButton.accessibilityLabel = "Cancel"
        cancelButton.accessibilityHint = "Dismisses without saving"
        navigationItem.leftBarButtonItem = cancelButton

        let saveButton = UIBarButtonItem(
            title: "Save",
            image: UIImage(systemName: "checkmark.circle.fill"),
            primaryAction: UIAction { [weak self] _ in
                self?.saveTapped()
            }
        )
        saveButton.accessibilityLabel = "Save"
        saveButton.accessibilityHint = "Saves the workout"
        navigationItem.rightBarButtonItem = saveButton
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorEffect = UIVibrancyEffect(
            blurEffect: UIBlurEffect(style: .systemUltraThinMaterial)
        )
        tableView.sectionHeaderTopPadding = 12
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EditorCell")
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func saveTapped() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showValidationAlert(message: "Please enter a workout name.")
            return
        }

        let updated = WorkoutTemplate(
            id: draftId,
            name: trimmedName,
            categoryId: draftCategoryId,
            exercises: draftExercises,
            iconName: draftIconName
        )

        switch mode {
        case .create:
            store.add(updated)
        case .edit(let original):
            let originalIds = Set(original.exercises.map(\.id))
            let updatedIds = Set(updated.exercises.map(\.id))
            let removedIds = originalIds.subtracting(updatedIds)
            if !removedIds.isEmpty {
                completionStore.clearCompletions(forExerciseIds: removedIds, in: updated.id)
                weightLogStore.deleteLogsForExercises(removedIds, in: updated.id)
            }
            store.update(updated)
        }

        HapticManager.shared.success()
        delegate?.workoutEditorDidSave(self, workout: updated)
        dismiss(animated: true)
    }

    private func showValidationAlert(message: String) {
        let alert = UIAlertController(
            title: "Missing Info", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func promptForName() {
        let alert = UIAlertController(title: "Workout Name", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "e.g., Push"
            field.text = self.draftName
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Done", style: .default) { [weak self] _ in
                guard let self else { return }
                let newName = alert.textFields?.first?.text ?? ""
                self.draftName = newName
                self.tableView.reloadSections(
                    IndexSet(integer: Section.details.rawValue), with: .none)
            })
        present(alert, animated: true)
    }

    /// Opens the exercise picker to select exercises from the library
    private func openExercisePicker() {
        let existingIds = Set(draftExercises.map(\.exerciseId))
        let picker = ExercisePickerViewController(existingExerciseIds: existingIds)
        picker.delegate = self
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    /// Edit sets/reps/duration for an existing exercise entry
    private func promptForExerciseDetails(editIndex: Int) {
        let exercise = draftExercises[editIndex]
        let alert = UIAlertController(
            title: exercise.name,
            message: "Edit sets, reps, and duration",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "Sets (e.g., 3)"
            field.text = exercise.sets
        }
        alert.addTextField { field in
            field.placeholder = "Reps (e.g., 8–12)"
            field.text = exercise.reps
        }
        alert.addTextField { field in
            field.placeholder = "Duration (e.g., 30 min, optional)"
            field.text = exercise.duration
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Update", style: .default) { [weak self] _ in
                guard let self else { return }
                let sets = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let reps = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let durationText = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let duration: String? = durationText.isEmpty ? nil : durationText

                self.draftExercises[editIndex] = WorkoutTemplate.Exercise(
                    id: exercise.id,
                    exerciseId: exercise.exerciseId,
                    sets: sets,
                    reps: reps,
                    defaultWeight: exercise.defaultWeight,
                    duration: duration
                )
                self.tableView.reloadSections(
                    IndexSet(integer: Section.exercises.rawValue), with: .none)
            })

        present(alert, animated: true)
    }

    /// Prompt for sets/reps when adding exercises from the picker
    private func promptSetsRepsForNewExercises(_ exercises: [ExerciseDefinition], index: Int = 0) {
        guard index < exercises.count else {
            tableView.reloadSections(IndexSet(integer: Section.exercises.rawValue), with: .none)
            return
        }

        let exercise = exercises[index]
        let alert = UIAlertController(
            title: exercise.name,
            message: "Set the number of sets and reps",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Sets (e.g., 3)"
            field.text = "3"
        }
        alert.addTextField { field in
            field.placeholder = "Reps (e.g., 8–12)"
        }
        alert.addTextField { field in
            field.placeholder = "Duration (optional)"
        }

        alert.addAction(UIAlertAction(title: "Skip", style: .cancel) { [weak self] _ in
            guard let self else { return }
            let entry = WorkoutTemplate.Exercise(
                id: UUID(),
                exerciseId: exercise.id,
                sets: "",
                reps: ""
            )
            self.draftExercises.append(entry)
            self.promptSetsRepsForNewExercises(exercises, index: index + 1)
        })
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self else { return }
            let sets = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reps = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let durationText = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let duration: String? = durationText.isEmpty ? nil : durationText

            let entry = WorkoutTemplate.Exercise(
                id: UUID(),
                exerciseId: exercise.id,
                sets: sets,
                reps: reps,
                duration: duration
            )
            self.draftExercises.append(entry)
            self.promptSetsRepsForNewExercises(exercises, index: index + 1)
        })
        present(alert, animated: true)
    }

    private func promptForCategory(sourceView: UIView? = nil, sourceRect: CGRect? = nil) {
        let alert = UIAlertController(title: "Category", message: nil, preferredStyle: .actionSheet)
        let categories = CategoryStore.shared.sortedCategories

        categories.forEach { category in
            let action = UIAlertAction(title: category.name, style: .default) { [weak self] _ in
                self?.draftCategoryId = category.id
                self?.tableView.reloadSections(
                    IndexSet(integer: Section.details.rawValue), with: .none)
            }
            if category.id == draftCategoryId {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            if let sourceView, let sourceRect {
                popover.sourceView = sourceView
                popover.sourceRect = sourceRect
                popover.permittedArrowDirections = [.up, .down]
            } else {
                popover.sourceView = view
                popover.sourceRect = CGRect(
                    x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
        }
        present(alert, animated: true)
    }

    private func promptForIcon() {
        let options = iconOptions.map { iconName in
            IconPickerViewController.IconOption(
                systemName: iconName,
                title: iconLabels[iconName] ?? "Custom"
            )
        }
        let selected = draftIconName ?? "figure.strengthtraining.traditional"
        let picker = IconPickerViewController(iconOptions: options, selectedIconName: selected)
        picker.delegate = self

        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    func iconPicker(
        _ controller: IconPickerViewController,
        didSelectIconNamed iconName: String
    ) {
        draftIconName = iconName
        tableView.reloadSections(
            IndexSet(integer: Section.details.rawValue), with: .none)
    }

    private func confirmDelete() {
        guard case .edit = mode else { return }
        let alert = UIAlertController(
            title: "Delete Workout",
            message: "This will remove the workout template from your library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.store.delete(id: self.draftId)
                self.delegate?.workoutEditorDidDelete(self, workoutId: self.draftId)
                self.dismiss(animated: true)
            })
        present(alert, animated: true)
    }
}

extension WorkoutEditorViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        switch mode {
        case .create:
            return 2
        case .edit:
            return 3
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .details:
            return 3
        case .exercises:
            return draftExercises.count + 1
        case .actions:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EditorCell", for: indexPath)
        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground

        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .details:
            if indexPath.row == 0 {
                var content = UIListContentConfiguration.valueCell()
                content.text = "Name"
                content.secondaryText = draftName.isEmpty ? "Tap to set" : draftName
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
            } else if indexPath.row == 1 {
                var content = UIListContentConfiguration.valueCell()
                content.text = "Category"
                content.secondaryText = CategoryStore.shared.category(for: draftCategoryId)?.name ?? "Uncategorized"
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
            } else {
                var content = UIListContentConfiguration.valueCell()
                content.text = "Icon"
                let iconName = draftIconName ?? "figure.strengthtraining.traditional"
                content.secondaryText = iconLabels[iconName] ?? "Custom"
                content.image = UIImage(systemName: iconName)
                content.imageProperties.tintColor = .systemBlue
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
            }

        case .exercises:
            if indexPath.row < draftExercises.count {
                let exercise = draftExercises[indexPath.row]
                var content = UIListContentConfiguration.subtitleCell()
                content.text = exercise.name
                var secondaryText = exercise.detailSummary

                // Show PR (skip for bodyweight exercises)
                let isBodyweightExercise = exercise.machineId == WeightMachine.bodyweightId
                if !isBodyweightExercise {
                    if let pr = weightLogStore.personalRecord(for: exercise.exerciseId) {
                        let prValue = pr.weight.truncatingRemainder(dividingBy: 1) == 0
                            ? String(format: "%.0f", pr.weight)
                            : String(format: "%.1f", pr.weight)
                        secondaryText += " • PR: \(prValue) \(pr.unit.symbol)"
                    }
                }

                // Show assigned machine name
                if let machineId = exercise.machineId,
                   let machine = machineStore.machine(for: machineId) {
                    secondaryText += " • \(machine.name)"
                }

                content.secondaryText = secondaryText
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
            } else {
                var content = UIListContentConfiguration.cell()
                content.text = "Add Exercise"
                content.image = UIImage(systemName: "plus.circle.fill")
                content.imageProperties.tintColor = .systemBlue
                cell.contentConfiguration = content
                cell.accessoryType = .none
            }

        case .actions:
            var content = UIListContentConfiguration.cell()
            content.text = "Delete Workout"
            content.textProperties.color = .systemRed
            cell.contentConfiguration = content
            cell.accessoryType = .none
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else { return }
        tableView.deselectRow(at: indexPath, animated: true)

        switch section {
        case .details:
            if indexPath.row == 0 {
                promptForName()
            } else if indexPath.row == 1 {
                let rect = tableView.rectForRow(at: indexPath)
                promptForCategory(sourceView: tableView, sourceRect: rect)
            } else {
                promptForIcon()
            }

        case .exercises:
            if indexPath.row < draftExercises.count {
                promptForExerciseDetails(editIndex: indexPath.row)
            } else {
                openExercisePicker()
            }

        case .actions:
            confirmDelete()
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let section = Section(rawValue: indexPath.section),
            section == .exercises,
            indexPath.row < draftExercises.count
        else {
            return nil
        }

        let exercise = draftExercises[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Remove") {
            [weak self] _, _, done in
            self?.draftExercises.remove(at: indexPath.row)
            self?.tableView.reloadSections(
                IndexSet(integer: Section.exercises.rawValue), with: .automatic)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")

        // Only show Reset PR if there's a PR for this exercise
        var actions = [delete]
        if weightLogStore.personalRecord(for: exercise.exerciseId) != nil {
            let resetPR = UIContextualAction(style: .normal, title: "Reset PR") {
                [weak self] _, _, done in
                self?.confirmResetPR(for: exercise)
                done(true)
            }
            resetPR.image = UIImage(systemName: "trophy.fill")
            resetPR.backgroundColor = .systemOrange
            actions.insert(resetPR, at: 0)
        }

        return UISwipeActionsConfiguration(actions: actions)
    }

    private func confirmResetPR(for exercise: WorkoutTemplate.Exercise) {
        let currentPR = weightLogStore.personalRecord(for: exercise.exerciseId)
        let prText = currentPR.map { "\(Int($0.weight)) \($0.unit.symbol)" } ?? "N/A"

        let alert = UIAlertController(
            title: "Reset PR for \(exercise.name)?",
            message: "Current PR: \(prText)\n\nThis will clear your personal record for this exercise. Your next logged weight will become the new PR.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            self?.weightLogStore.resetPR(for: exercise.exerciseId)
            self?.tableView.reloadSections(
                IndexSet(integer: Section.exercises.rawValue), with: .automatic)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDragDelegate

extension WorkoutEditorViewController: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard indexPath.section == Section.exercises.rawValue,
              indexPath.row < draftExercises.count else {
            return []
        }
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = indexPath
        return [item]
    }
}

// MARK: - UITableViewDropDelegate

extension WorkoutEditorViewController: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        guard let dest = destinationIndexPath,
              dest.section == Section.exercises.rawValue,
              dest.row < draftExercises.count,
              session.localDragSession != nil else {
            return UITableViewDropProposal(operation: .cancel)
        }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: any UITableViewDropCoordinator) {
        guard let item = coordinator.items.first,
              let sourceIndexPath = item.dragItem.localObject as? IndexPath,
              let destinationIndexPath = coordinator.destinationIndexPath,
              destinationIndexPath.section == Section.exercises.rawValue,
              destinationIndexPath.row < draftExercises.count else {
            return
        }

        tableView.performBatchUpdates {
            let exercise = draftExercises.remove(at: sourceIndexPath.row)
            draftExercises.insert(exercise, at: destinationIndexPath.row)
            tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
        }
        coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
    }
}

// MARK: - ExercisePickerViewControllerDelegate

extension WorkoutEditorViewController: ExercisePickerViewControllerDelegate {
    func exercisePicker(_ controller: ExercisePickerViewController,
                        didSelect exercises: [ExerciseDefinition]) {
        promptSetsRepsForNewExercises(exercises)
    }
}
