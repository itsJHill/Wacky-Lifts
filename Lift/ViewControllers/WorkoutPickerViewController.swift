import UIKit

protocol WorkoutPickerViewControllerDelegate: AnyObject {
    func workoutPicker(
        _ controller: WorkoutPickerViewController, didSelectWorkouts workouts: [WorkoutTemplate])
}

final class WorkoutPickerViewController: UIViewController {
    struct Section: Hashable {
        let title: String
    }

    private let allWorkouts: [WorkoutTemplate]
    private var selectedWorkoutIDs: Set<UUID>
    weak var delegate: WorkoutPickerViewControllerDelegate?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, WorkoutTemplate>!

    private let searchController = UISearchController(searchResultsController: nil)
    private var filteredWorkouts: [WorkoutTemplate] = []

    init(allWorkouts: [WorkoutTemplate], preselected: [WorkoutTemplate]) {
        self.allWorkouts = allWorkouts
        self.selectedWorkoutIDs = Set(preselected.map { $0.id })
        super.init(nibName: nil, bundle: nil)
        self.filteredWorkouts = allWorkouts
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        applyLiquidGlassBackground()
        navigationItem.title = "Add Workouts"
        navigationItem.largeTitleDisplayMode = .never
        configureNavBar()
        configureCollectionView()
        configureDataSource()
        applySnapshot(animated: false)
        configureSearch()
    }

    private func configureNavBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            image: UIImage(systemName: "checkmark.circle.fill"),
            primaryAction: UIAction { [weak self] _ in
                self?.commitSelection()
            }
        )
        navigationItem.rightBarButtonItem?.style = .done
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
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, WorkoutTemplate>(
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

        collectionView.delegate = self
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, WorkoutTemplate>()
        let section = Section(title: "Workouts")
        snapshot.appendSections([section])
        snapshot.appendItems(filteredWorkouts, toSection: section)
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func commitSelection() {
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
                    || workout.category.rawValue.localizedCaseInsensitiveContains(query)
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
        subtitleLabel.text = workout.category.rawValue
        setSelectedState(selected, animated: false)
    }

    func setSelectedState(_ selected: Bool, animated: Bool) {
        let image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        let update = {
            self.checkmarkView.image = image
            self.contentView.layer.borderWidth = selected ? 1.5 : 0
            self.contentView.layer.borderColor =
                selected
                ? UIColor.systemBlue.withAlphaComponent(0.6).cgColor : UIColor.clear.cgColor
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
