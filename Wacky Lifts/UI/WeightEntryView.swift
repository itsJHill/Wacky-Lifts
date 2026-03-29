import UIKit

protocol WeightEntryViewDelegate: AnyObject {
    func weightEntryView(_ view: WeightEntryView, didConfirmWeight weight: Double, wasModified: Bool)
}

final class WeightEntryView: UIView {

    weak var delegate: WeightEntryViewDelegate?

    private let weightLogStore = WeightLogStore.shared

    private(set) var weight: Double = 0 {
        didSet {
            updateWeightLabel()
        }
    }

    private var isConfirmed: Bool = false {
        didSet {
            updateConfirmButton()
        }
    }

    private var isPR: Bool = false {
        didSet {
            prBadge.isHidden = !isPR
        }
    }

    /// Tracks if user modified the weight via +/- buttons
    private var wasModified: Bool = false

    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // Weight controls
    private let weightLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let weightMinusButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        button.tintColor = .secondaryLabel
        button.accessibilityLabel = "Decrease weight"
        return button
    }()

    private let weightPlusButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        button.tintColor = .secondaryLabel
        button.accessibilityLabel = "Increase weight"
        return button
    }()

    // Confirm button
    private let confirmButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "checkmark.circle"), for: .normal)
        button.tintColor = .systemBlue
        button.accessibilityLabel = "Save weight"
        return button
    }()

    // PR Badge
    private let prBadge: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
        container.layer.cornerRadius = 10
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "trophy.fill"))
        icon.tintColor = .systemYellow
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "PR"
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .systemYellow

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 12),
            icon.heightAnchor.constraint(equalToConstant: 12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        ])

        return container
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        // Weight controls in a horizontal stack
        let weightStack = UIStackView(arrangedSubviews: [weightMinusButton, weightLabel, weightPlusButton])
        weightStack.axis = .horizontal
        weightStack.spacing = 8
        weightStack.alignment = .center

        // Spacer pushes PR badge to trailing edge
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        containerStack.addArrangedSubview(weightStack)
        containerStack.addArrangedSubview(confirmButton)
        containerStack.addArrangedSubview(spacer)
        containerStack.addArrangedSubview(prBadge)

        addSubview(containerStack)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 68),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            weightLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
        ])

        // Button actions
        weightMinusButton.addTarget(self, action: #selector(decreaseWeight), for: .touchUpInside)
        weightPlusButton.addTarget(self, action: #selector(increaseWeight), for: .touchUpInside)
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)

        updateWeightLabel()
        updateConfirmButton()
    }

    func configure(weight: Double, isConfirmed: Bool, isPR: Bool) {
        self.weight = weight
        self.isConfirmed = isConfirmed
        self.isPR = isPR
        self.wasModified = false // Reset on configure
        updateConfirmButton()
    }

    private func updateWeightLabel() {
        let unit = weightLogStore.preferredUnit
        if weight == floor(weight) {
            weightLabel.text = "\(Int(weight)) \(unit.symbol)"
        } else {
            weightLabel.text = String(format: "%.1f %@", weight, unit.symbol)
        }
    }

    private func updateConfirmButton() {
        if isConfirmed {
            confirmButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
            confirmButton.tintColor = .systemGreen
        } else {
            confirmButton.setImage(UIImage(systemName: "checkmark.circle"), for: .normal)
            confirmButton.tintColor = .systemBlue
        }
    }

    @objc private func decreaseWeight() {
        let increment = weightLogStore.preferredUnit.increment
        weight = max(0, weight - increment)
        wasModified = true
        HapticManager.shared.light()
        // Reset confirmed state when weight changes
        if isConfirmed {
            isConfirmed = false
            isPR = false
        }
    }

    @objc private func increaseWeight() {
        let increment = weightLogStore.preferredUnit.increment
        weight += increment
        wasModified = true
        HapticManager.shared.light()
        // Reset confirmed state when weight changes
        if isConfirmed {
            isConfirmed = false
            isPR = false
        }
    }

    @objc private func confirmTapped() {
        guard weight > 0 else { return }
        isConfirmed = true
        HapticManager.shared.success()
        delegate?.weightEntryView(self, didConfirmWeight: weight, wasModified: wasModified)
    }

    /// Called after delegate saves the log to update PR status
    func markAsPR(_ isPR: Bool) {
        self.isPR = isPR
    }
}
