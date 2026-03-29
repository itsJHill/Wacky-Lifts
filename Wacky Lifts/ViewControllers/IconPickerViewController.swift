@preconcurrency import UIKit

protocol IconPickerViewControllerDelegate: AnyObject {
    func iconPicker(_ controller: IconPickerViewController, didSelectIconNamed iconName: String)
}

final class IconPickerViewController: UIViewController {
    struct IconOption: Hashable, Sendable {
        let systemName: String
        let title: String
    }

    private enum Section: Hashable, Sendable {
        case main
    }

    weak var delegate: IconPickerViewControllerDelegate?

    private let iconOptions: [IconOption]
    private let selectedIconName: String?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, IconOption>!

    init(iconOptions: [IconOption], selectedIconName: String?) {
        self.iconOptions = iconOptions
        self.selectedIconName = selectedIconName
        super.init(nibName: nil, bundle: nil)
        title = "Choose Icon"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavBar()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    private func configureNavBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout {
            _, environment -> NSCollectionLayoutSection? in
            let availableWidth = environment.container.effectiveContentSize.width - 32
            let minItemWidth: CGFloat = 96
            let spacing: CGFloat = 12
            let columns = max(
                2,
                Int((availableWidth + spacing) / (minItemWidth + spacing))
            )

            let itemFraction = 1.0 / CGFloat(columns)
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(itemFraction),
                heightDimension: .absolute(92)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(92)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(12)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 12, leading: 16, bottom: 20, trailing: 16
            )
            return section
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.allowsMultipleSelection = false
        collectionView.alwaysBounceVertical = true
        collectionView.isScrollEnabled = true

        collectionView.register(
            IconPickerCell.self,
            forCellWithReuseIdentifier: IconPickerCell.reuseIdentifier
        )

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, IconOption>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, option in
            guard
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: IconPickerCell.reuseIdentifier,
                    for: indexPath
                ) as? IconPickerCell
            else { return UICollectionViewCell() }

            let isSelected = option.systemName == self?.selectedIconName
            cell.configure(with: option, selected: isSelected)
            return cell
        }

        collectionView.delegate = self
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, IconOption>()
        snapshot.appendSections([.main])
        snapshot.appendItems(iconOptions, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)

        if let selectedIconName,
            let index = iconOptions.firstIndex(where: { $0.systemName == selectedIconName })
        {
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }
}

extension IconPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let option = dataSource.itemIdentifier(for: indexPath) else { return }
        HapticManager.shared.selection()
        delegate?.iconPicker(self, didSelectIconNamed: option.systemName)
        dismiss(animated: true)
    }
}

final class IconPickerCell: UICollectionViewCell {
    static let reuseIdentifier = "IconPickerCell"

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.cornerRadius = 16
        contentView.layer.masksToBounds = true
    }

    private func configureViews() {
        contentView.backgroundColor = .secondarySystemBackground

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.layer.masksToBounds = true
        contentView.addSubview(blurView)

        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .vertical)
        iconView.setContentCompressionResistancePriority(.required, for: .vertical)

        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .center

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            iconView.heightAnchor.constraint(equalToConstant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 28),
        ])
    }

    func configure(with option: IconPickerViewController.IconOption, selected: Bool) {
        iconView.image = UIImage(systemName: option.systemName)
        titleLabel.text = option.title
        setSelectedState(selected, animated: false)
    }

    private func setSelectedState(_ selected: Bool, animated: Bool) {
        let update = {
            self.contentView.layer.borderWidth = selected ? 1.5 : 0
            self.contentView.layer.borderColor = selected ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: update)
        } else {
            update()
        }
    }
}
