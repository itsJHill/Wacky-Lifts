@preconcurrency import UIKit

protocol WorkoutPickerViewControllerDelegate: AnyObject {
    func workoutPicker(
        _ controller: WorkoutPickerViewController, didSelectWorkouts workouts: [WorkoutTemplate])
}

final class WorkoutPickerViewController: UIViewController {
    private let allWorkouts: [WorkoutTemplate]
    private var selectedWorkoutIDs: Set<UUID>
    weak var delegate: WorkoutPickerViewControllerDelegate?

    /// If true, shows a "Create New Workout" button at the bottom of the list.
    /// Passed through from the presenting VC, used by ProgramEditor.
    let allowsCreation: Bool

    /// Carried context so callers can identify which week/day this picker is for.
    /// Set by the presenting VC. Not used internally; passed back via delegate.
    var dayContext: (weekIndex: Int, weekday: Weekday)?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<UUID, WorkoutTemplate>!

    private let searchController = UISearchController(searchResultsController: nil)
    private var filteredWorkouts: [WorkoutTemplate] = []

    init(allWorkouts: [WorkoutTemplate], preselected: [WorkoutTemplate], allowsCreation: Bool = false) {
        self.allWorkouts = allWorkouts
        self.selectedWorkoutIDs = Set(preselected.map { $0.id })
        self.allowsCreation = allowsCreation
        super.init(nibName: nil, bundle: nil)
        self.filteredWorkouts = allWorkouts
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = "Add Workouts"
        navigationItem.largeTitleDisplayMode = .never
        configureNavBar()
        configureCollectionView()
        configureDataSource()
        applySnapshot(animated: false)
        configureSearch()
    }

    private func configureNavBar() {
        let cancelButton = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        cancelButton.accessibilityLabel = "Cancel"
        cancelButton.accessibilityHint = "Dismisses without saving"
        navigationItem.leftBarButtonItem = cancelButton

        var rightItems: [UIBarButtonItem] = []

        if allowsCreation {
            let createButton = UIBarButtonItem(
                image: UIImage(systemName: "plus.circle"),
                style: .plain,
                target: self,
                action: #selector(createWorkoutTapped)
            )
            createButton.accessibilityLabel = "Create new workout"
            rightItems.append(createButton)
        }

        let doneButton = UIBarButtonItem(
            title: "Done",
            image: UIImage(systemName: "checkmark.circle.fill"),
            primaryAction: UIAction { [weak self] _ in
                self?.commitSelection()
            }
        )
        doneButton.accessibilityLabel = "Done"
        doneButton.accessibilityHint = "Saves selected workouts"
        rightItems.append(doneButton)

        navigationItem.rightBarButtonItems = rightItems
    }

    @objc private func createWorkoutTapped() {
        let editor = WorkoutEditorViewController(mode: .create)
        editor.delegate = self
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func configureSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search workouts"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, _ -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(56)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(56)
            )
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 8, leading: 16, bottom: 16, trailing: 16)
            section.interGroupSpacing = 10

            // Add section header
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(32)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]

            return section
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.allowsMultipleSelection = true
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        collectionView.register(
            WorkoutPickerCell.self, forCellWithReuseIdentifier: WorkoutPickerCell.reuseIdentifier)
        collectionView.register(
            SectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: SectionHeaderView.reuseIdentifier)
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<UUID, WorkoutTemplate>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, workout in
            guard
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: WorkoutPickerCell.reuseIdentifier,
                    for: indexPath
                ) as? WorkoutPickerCell
            else {
                return UICollectionViewCell()
            }

            let isSelected = self?.selectedWorkoutIDs.contains(workout.id) == true
            cell.configure(with: workout, selected: isSelected)
            return cell
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionHeader,
                  let header = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: SectionHeaderView.reuseIdentifier,
                    for: indexPath
                  ) as? SectionHeaderView,
                  let categoryId = self.dataSource.sectionIdentifier(for: indexPath.section)
            else {
                return UICollectionReusableView()
            }
            let categoryName = CategoryStore.shared.category(for: categoryId)?.name ?? "Uncategorized"
            header.configure(title: categoryName)
            return header
        }

        collectionView.delegate = self
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<UUID, WorkoutTemplate>()

        // Group filtered workouts by categoryId
        var categorized: [UUID: [WorkoutTemplate]] = [:]
        for workout in filteredWorkouts {
            categorized[workout.categoryId, default: []].append(workout)
        }

        // Add sections in category order
        let sortedCategories = CategoryStore.shared.sortedCategories
        let orderedCategoryIds = sortedCategories.map(\.id).filter { categorized[$0] != nil }
        snapshot.appendSections(orderedCategoryIds)

        for categoryId in orderedCategoryIds {
            if let workouts = categorized[categoryId] {
                snapshot.appendItems(workouts, toSection: categoryId)
            }
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func commitSelection() {
        HapticManager.shared.success()
        let selected = allWorkouts.filter { selectedWorkoutIDs.contains($0.id) }
        delegate?.workoutPicker(self, didSelectWorkouts: selected)
        dismiss(animated: true)
    }

    private func updateSelection(for workout: WorkoutTemplate) {
        if selectedWorkoutIDs.contains(workout.id) {
            selectedWorkoutIDs.remove(workout.id)
        } else {
            selectedWorkoutIDs.insert(workout.id)
        }
    }

    private func refreshVisibleSelection() {
        for cell in collectionView.visibleCells {
            guard
                let indexPath = collectionView.indexPath(for: cell),
                let workout = dataSource.itemIdentifier(for: indexPath),
                let pickerCell = cell as? WorkoutPickerCell
            else { continue }

            let isSelected = selectedWorkoutIDs.contains(workout.id)
            pickerCell.setSelectedState(isSelected, animated: true)
        }
    }
}

extension WorkoutPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let workout = dataSource.itemIdentifier(for: indexPath) else { return }
        updateSelection(for: workout)
        refreshVisibleSelection()
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}

extension WorkoutPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query =
            searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if query.isEmpty {
            filteredWorkouts = allWorkouts
        } else {
            filteredWorkouts = allWorkouts.filter { workout in
                workout.name.localizedCaseInsensitiveContains(query)
                    || workout.categoryName.localizedCaseInsensitiveContains(query)
            }
        }
        applySnapshot(animated: true)
    }
}

final class WorkoutPickerCell: UICollectionViewCell {
    static let reuseIdentifier = "WorkoutPickerCell"

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checkmarkView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.cornerRadius = 18
        contentView.layer.masksToBounds = true
    }

    private func configureViews() {
        contentView.backgroundColor = .secondarySystemBackground

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 18
        blurView.layer.masksToBounds = true
        contentView.addSubview(blurView)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.tintColor = .systemBlue
        checkmarkView.setContentHuggingPriority(.required, for: .horizontal)

        let container = UIStackView(arrangedSubviews: [stack, checkmarkView])
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            checkmarkView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    func configure(with workout: WorkoutTemplate, selected: Bool) {
        titleLabel.text = workout.name
        subtitleLabel.text = "\(workout.exercises.count) exercises"
        setSelectedState(selected, animated: false)
    }

    func setSelectedState(_ selected: Bool, animated: Bool) {
        let image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        let update = {
            self.checkmarkView.image = image
            self.contentView.layer.borderWidth = selected ? 1.5 : 0
            self.contentView.layer.borderColor = selected ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
        }

        if animated {
            UIView.transition(
                with: checkmarkView, duration: 0.2, options: .transitionCrossDissolve,
                animations: update)
        } else {
            update()
        }
    }
}

private final class SectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "SectionHeaderView"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}

// MARK: - WorkoutEditorViewControllerDelegate

extension WorkoutPickerViewController: WorkoutEditorViewControllerDelegate {
    func workoutEditorDidSave(_ controller: WorkoutEditorViewController, workout: WorkoutTemplate) {
        // Auto-select the newly created workout
        selectedWorkoutIDs.insert(workout.id)
        // Reload data so the new workout appears in the list
        filteredWorkouts = WorkoutLibraryStore.shared.templates
        applySnapshot(animated: true)
        refreshVisibleSelection()
    }

    func workoutEditorDidDelete(_ controller: WorkoutEditorViewController, workoutId: WorkoutTemplate.ID) {}
}
