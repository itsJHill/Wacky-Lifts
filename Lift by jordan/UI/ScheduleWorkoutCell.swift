import UIKit

protocol ScheduleWorkoutCellDelegate: AnyObject {
    func scheduleWorkoutCell(_ cell: ScheduleWorkoutCell, didToggleExercise exercise: WorkoutTemplate.Exercise, in workout: WorkoutTemplate)
    func scheduleWorkoutCell(_ cell: ScheduleWorkoutCell, didConfirmSetWeights setWeights: [Double], wasModified: Bool, for exercise: WorkoutTemplate.Exercise, in workout: WorkoutTemplate) -> Bool
    func scheduleWorkoutCellDidToggleExpand(_ cell: ScheduleWorkoutCell, exerciseId: UUID)
    func scheduleWorkoutCellNeedsResize(_ cell: ScheduleWorkoutCell)
    func scheduleWorkoutCellDidTapStartWorkout(_ cell: ScheduleWorkoutCell, workout: WorkoutTemplate)
    func scheduleWorkoutCell(_ cell: ScheduleWorkoutCell, didTapTimerForExercise exercise: WorkoutTemplate.Exercise, in workout: WorkoutTemplate)
    func scheduleWorkoutCellDidLongPress(_ cell: ScheduleWorkoutCell)
}

final class ScheduleWorkoutCell: UITableViewCell {
    static let reuseIdentifier = "ScheduleWorkoutCell"

    weak var delegate: ScheduleWorkoutCellDelegate?

    private var workout: WorkoutTemplate?
    private var exerciseCompletions: [UUID: Bool] = [:]
    private var exerciseLogs: [UUID: ExerciseLog] = [:]
    private var expandedExercises: Set<UUID> = []

    /// Per-exercise set weights being edited (keyed by exercise ID)
    private var editingSetWeights: [UUID: [Double]] = [:]
    /// Per-exercise initial weights snapshot for wasModified detection
    private var initialSetWeights: [UUID: [Double]] = [:]
    /// Per-exercise stacks for set rows (keyed by exercise ID)
    private var setRowStacks: [UUID: UIStackView] = [:]
    /// Per-exercise containers for scrolling (keyed by exercise ID)
    private var exerciseContainers: [UUID: UIStackView] = [:]

    private var progressToStartButtonConstraint: NSLayoutConstraint!
    private var progressToTrailingConstraint: NSLayoutConstraint!

    private let weightLogStore = WeightLogStore.shared

    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let progressLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let startButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: config), for: .normal)
        button.tintColor = .systemBlue
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private let exercisesStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let innerCardView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        editingSetWeights.removeAll()
        initialSetWeights.removeAll()
        setRowStacks.removeAll()
        exerciseContainers.removeAll()
        innerCardView.layer.borderWidth = 0
        innerCardView.backgroundColor = .clear
    }

    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(innerCardView)
        innerCardView.addSubview(containerStack)

        headerView.addSubview(iconImageView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(progressLabel)
        headerView.addSubview(startButton)

        startButton.addTarget(self, action: #selector(startButtonTapped), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressCellHandler(_:)))
        containerStack.addGestureRecognizer(longPress)

        containerStack.addArrangedSubview(headerView)
        containerStack.addArrangedSubview(exercisesStack)

        NSLayoutConstraint.activate([
            innerCardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            innerCardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 7),
            innerCardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
            innerCardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),

            containerStack.topAnchor.constraint(equalTo: innerCardView.topAnchor, constant: 8),
            containerStack.leadingAnchor.constraint(equalTo: innerCardView.leadingAnchor, constant: 12),
            containerStack.trailingAnchor.constraint(equalTo: innerCardView.trailingAnchor, constant: -12),
            containerStack.bottomAnchor.constraint(equalTo: innerCardView.bottomAnchor, constant: -8),

            headerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),

            iconImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            progressLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            progressLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            startButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            startButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 28),
            startButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Toggle between these based on startButton visibility
        progressToStartButtonConstraint = progressLabel.trailingAnchor.constraint(lessThanOrEqualTo: startButton.leadingAnchor, constant: -8)
        progressToTrailingConstraint = progressLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor)
        progressToTrailingConstraint.isActive = true
    }

    func configure(with workout: WorkoutTemplate, completions: [UUID: Bool], logs: [UUID: ExerciseLog] = [:], expandedExercises: Set<UUID> = [], isProgramWorkout: Bool = false, programBorderColor: UIColor? = nil) {
        self.workout = workout
        self.exerciseCompletions = completions
        self.exerciseLogs = logs
        self.expandedExercises = expandedExercises
        editingSetWeights.removeAll()
        initialSetWeights.removeAll()
        setRowStacks.removeAll()

        let iconName = workout.iconName ?? "figure.strengthtraining.traditional"
        iconImageView.image = UIImage(systemName: iconName)
        titleLabel.text = workout.name

        let completedCount = completions.values.filter { $0 }.count
        let totalCount = workout.exercises.count
        let isFullyCompleted = completedCount == totalCount && totalCount > 0
        let hasPR = logs.values.contains { $0.isPersonalRecord }

        innerCardView.backgroundColor = .secondarySystemBackground

        if isProgramWorkout {
            innerCardView.layer.borderWidth = 3
            innerCardView.layer.borderColor = (programBorderColor ?? .systemIndigo).cgColor
        }

        if isFullyCompleted {
            if hasPR {
                progressLabel.text = "Complete 🏆"
            } else {
                progressLabel.text = "Complete"
            }
            progressLabel.textColor = .systemGreen
            iconImageView.tintColor = .systemGreen
        } else {
            progressLabel.text = "\(completedCount)/\(totalCount)"
            progressLabel.textColor = .secondaryLabel
            iconImageView.tintColor = .systemBlue
        }

        let showStart = workout.isAllDuration
        startButton.isHidden = !showStart
        progressToStartButtonConstraint.isActive = showStart
        progressToTrailingConstraint.isActive = !showStart

        exercisesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for exercise in workout.exercises {
            let isCompleted = completions[exercise.id] ?? false
            let log = logs[exercise.id]
            let row = createExerciseRow(exercise: exercise, isCompleted: isCompleted, log: log)
            exercisesStack.addArrangedSubview(row)
        }
    }

    // MARK: - Set Count Parsing

    private func parseSetCount(from setsString: String) -> Int {
        // Extract first integer from strings like "3", "3-5", "3 sets", etc.
        let scanner = Scanner(string: setsString)
        scanner.charactersToBeSkipped = CharacterSet.decimalDigits.inverted
        var value: Int = 0
        if scanner.scanInt(&value), value > 0 {
            return value
        }
        return 3 // sensible default
    }

    // MARK: - Weight Formatting

    private func displayWeight(_ weight: Double, for exercise: WorkoutTemplate.Exercise) -> String {
        weightLogStore.displayWeight(weight, for: exercise.exerciseId, unit: weightLogStore.preferredUnit)
    }

    private func weightSummaryText(for weights: [Double], exercise: WorkoutTemplate.Exercise) -> String {
        guard !weights.isEmpty else { return displayWeight(0, for: exercise) }

        let allSame = Set(weights).count == 1
        if allSame {
            return "\(weights.count) × \(displayWeight(weights[0], for: exercise))"
        } else {
            let parts = weights.map { displayWeight($0, for: exercise) }
            return parts.joined(separator: " → ")
        }
    }

    // MARK: - Exercise Row

    private func createExerciseRow(exercise: WorkoutTemplate.Exercise, isCompleted: Bool, log: ExerciseLog?) -> UIView {
        let outerContainer = UIStackView()
        outerContainer.axis = .vertical
        outerContainer.spacing = 0
        outerContainer.translatesAutoresizingMaskIntoConstraints = false
        exerciseContainers[exercise.id] = outerContainer

        // Exercise info row
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let imageName = isCompleted ? "checkmark.circle.fill" : "circle"
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.tintColor = isCompleted ? .systemGreen : .tertiaryLabel
        button.accessibilityIdentifier = "exercise_\(exercise.id.uuidString)"
        button.addTarget(self, action: #selector(exerciseButtonTapped(_:)), for: .touchUpInside)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = isCompleted ? .tertiaryLabel : .secondaryLabel
        label.numberOfLines = 0

        // Build exercise text
        let isBodyweightMachine = exercise.machineId == WeightMachine.bodyweightId
        var exerciseText = "\(exercise.name) — \(exercise.detailSummary)"
        if !isBodyweightMachine, let pr = weightLogStore.personalRecord(for: exercise.exerciseId), pr.weight != 0 {
            exerciseText += " • PR: \(displayWeight(pr.weight, for: exercise))"
        }
        label.text = exerciseText

        if isCompleted {
            let attributedText = NSMutableAttributedString(string: label.text ?? "")
            attributedText.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributedText.length))
            label.attributedText = attributedText
        }

        // Inline timer button for duration exercises in mixed workouts
        let isAllDuration = workout?.isAllDuration ?? false
        let hasDuration = exercise.durationInSeconds != nil
        let showTimerButton = hasDuration && !isAllDuration && !isCompleted

        let timerButton = UIButton(type: .system)
        timerButton.translatesAutoresizingMaskIntoConstraints = false
        let timerConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        timerButton.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: timerConfig), for: .normal)
        timerButton.tintColor = .systemBlue
        timerButton.accessibilityIdentifier = "timer_\(exercise.id.uuidString)"
        timerButton.addTarget(self, action: #selector(exerciseTimerTapped(_:)), for: .touchUpInside)
        timerButton.isHidden = !showTimerButton

        // PR badge on exercise row if logged
        let prBadge = UIImageView(image: UIImage(systemName: "trophy.fill"))
        prBadge.translatesAutoresizingMaskIntoConstraints = false
        prBadge.tintColor = .systemYellow
        prBadge.isHidden = !(log?.isPersonalRecord ?? false)

        container.addSubview(button)
        container.addSubview(label)
        container.addSubview(timerButton)
        container.addSubview(prBadge)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),

            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 34),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: timerButton.leadingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            timerButton.trailingAnchor.constraint(equalTo: prBadge.leadingAnchor, constant: -4),
            timerButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            timerButton.widthAnchor.constraint(equalToConstant: 28),
            timerButton.heightAnchor.constraint(equalToConstant: 28),

            prBadge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            prBadge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            prBadge.widthAnchor.constraint(equalToConstant: 16),
            prBadge.heightAnchor.constraint(equalToConstant: 16),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(exerciseRowTapped(_:)))
        container.addGestureRecognizer(tapGesture)
        container.accessibilityIdentifier = exercise.id.uuidString

        outerContainer.addArrangedSubview(container)

        // Per-set weight section (shown when completed, skipped for duration-only and bodyweight exercises)
        if isCompleted && !exercise.isDurationOnly && !isBodyweightMachine {
            let setSection = createSetSection(exercise: exercise, log: log)
            outerContainer.addArrangedSubview(setSection)
        }

        return outerContainer
    }

    // MARK: - Per-Set Section

    private func createSetSection(exercise: WorkoutTemplate.Exercise, log: ExerciseLog?) -> UIView {
        let sectionStack = UIStackView()
        sectionStack.axis = .vertical
        sectionStack.spacing = 0
        sectionStack.translatesAutoresizingMaskIntoConstraints = false

        let isExpanded = expandedExercises.contains(exercise.id)
        let hasLog = log != nil

        // Initialize set weights
        let setCount = parseSetCount(from: exercise.sets)
        let prWeight = weightLogStore.personalRecord(for: exercise.exerciseId)?.weight
        let defaultWeight = log?.weight ?? prWeight ?? exercise.defaultWeight ?? 0
        let weights: [Double]
        if let existingWeights = log?.setWeights {
            weights = existingWeights
        } else if let logWeight = log?.weight, logWeight > 0 {
            // Legacy single-weight log — fill all sets with that weight
            weights = Array(repeating: logWeight, count: setCount)
        } else {
            weights = Array(repeating: defaultWeight, count: setCount)
        }

        editingSetWeights[exercise.id] = weights
        initialSetWeights[exercise.id] = weights

        // Summary row (always visible)
        let summaryRow = createSummaryRow(exercise: exercise, weights: weights, isExpanded: isExpanded, isConfirmed: hasLog, isPR: log?.isPersonalRecord ?? false)
        sectionStack.addArrangedSubview(summaryRow)

        // Expandable set rows container
        let setsContainer = UIStackView()
        setsContainer.axis = .vertical
        setsContainer.spacing = 4
        setsContainer.translatesAutoresizingMaskIntoConstraints = false
        setsContainer.isHidden = !isExpanded
        setsContainer.alpha = isExpanded ? 1 : 0

        // Store reference to rebuild set rows
        setRowStacks[exercise.id] = setsContainer

        // Per-set rows
        for i in 0..<weights.count {
            let setRow = createSetRow(exercise: exercise, setIndex: i, weight: weights[i])
            setsContainer.addArrangedSubview(setRow)
        }

        // Add Set button
        let addSetButton = createAddSetButton(exercise: exercise)
        setsContainer.addArrangedSubview(addSetButton)

        sectionStack.addArrangedSubview(setsContainer)

        // Show per-set PR trophies if this exercise already has a PR logged
        if log?.isPersonalRecord == true {
            updateSetPRIndicators(containerKey: exercise.id, exerciseId: exercise.exerciseId, weights: weights, isPR: true)
        }

        return sectionStack
    }

    // MARK: - Summary Row

    private func createSummaryRow(exercise: WorkoutTemplate.Exercise, weights: [Double], isExpanded: Bool, isConfirmed: Bool, isPR: Bool) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.accessibilityIdentifier = "summary_\(exercise.id.uuidString)"

        // Chevron
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let chevron = UIImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: isExpanded ? "chevron.down" : "chevron.right", withConfiguration: chevronConfig)
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .center
        chevron.tag = 100 // tag to find later

        // Summary label
        let summaryLabel = UILabel()
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = .preferredFont(forTextStyle: .caption1)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.text = weightSummaryText(for: weights, exercise: exercise)
        summaryLabel.tag = 101

        // Confirm button
        let confirmButton = UIButton(type: .system)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        if isConfirmed {
            confirmButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
            confirmButton.tintColor = .systemGreen
        } else {
            confirmButton.setImage(UIImage(systemName: "checkmark.circle"), for: .normal)
            confirmButton.tintColor = .systemBlue
        }
        confirmButton.accessibilityIdentifier = "confirm_\(exercise.id.uuidString)"
        confirmButton.addTarget(self, action: #selector(confirmSetsTapped(_:)), for: .touchUpInside)

        // PR badge
        let prBadge = UIView()
        prBadge.translatesAutoresizingMaskIntoConstraints = false
        prBadge.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
        prBadge.layer.cornerRadius = 10
        prBadge.isHidden = !isPR

        let prStack = UIStackView()
        prStack.axis = .horizontal
        prStack.spacing = 4
        prStack.alignment = .center
        prStack.translatesAutoresizingMaskIntoConstraints = false

        let prIcon = UIImageView(image: UIImage(systemName: "trophy.fill"))
        prIcon.tintColor = .systemYellow
        prIcon.translatesAutoresizingMaskIntoConstraints = false

        let prLabel = UILabel()
        prLabel.text = "PR"
        prLabel.font = .systemFont(ofSize: 12, weight: .bold)
        prLabel.textColor = .systemYellow

        prStack.addArrangedSubview(prIcon)
        prStack.addArrangedSubview(prLabel)
        prBadge.addSubview(prStack)

        container.addSubview(chevron)
        container.addSubview(summaryLabel)
        container.addSubview(confirmButton)
        container.addSubview(prBadge)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),

            chevron.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 20),
            chevron.heightAnchor.constraint(equalToConstant: 20),

            summaryLabel.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 8),
            summaryLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            summaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: confirmButton.leadingAnchor, constant: -8),

            confirmButton.trailingAnchor.constraint(equalTo: prBadge.leadingAnchor, constant: -8),
            confirmButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            confirmButton.widthAnchor.constraint(equalToConstant: 28),
            confirmButton.heightAnchor.constraint(equalToConstant: 28),

            prBadge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            prBadge.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            prIcon.widthAnchor.constraint(equalToConstant: 12),
            prIcon.heightAnchor.constraint(equalToConstant: 12),
            prStack.topAnchor.constraint(equalTo: prBadge.topAnchor, constant: 4),
            prStack.bottomAnchor.constraint(equalTo: prBadge.bottomAnchor, constant: -4),
            prStack.leadingAnchor.constraint(equalTo: prBadge.leadingAnchor, constant: 8),
            prStack.trailingAnchor.constraint(equalTo: prBadge.trailingAnchor, constant: -8),
        ])

        // Tap to toggle expand/collapse
        let tap = UITapGestureRecognizer(target: self, action: #selector(summaryRowTapped(_:)))
        container.addGestureRecognizer(tap)

        return container
    }

    // MARK: - Set Row

    /// Tag base for per-set PR trophy icons (tag = 300 + setIndex)
    private static let prTrophyTagBase = 300

    private func createSetRow(exercise: WorkoutTemplate.Exercise, setIndex: Int, weight: Double) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let setLabel = UILabel()
        setLabel.translatesAutoresizingMaskIntoConstraints = false
        setLabel.font = .preferredFont(forTextStyle: .caption1)
        setLabel.textColor = .tertiaryLabel
        setLabel.text = "Set \(setIndex + 1)"

        let minusButton = UIButton(type: .system)
        minusButton.translatesAutoresizingMaskIntoConstraints = false
        minusButton.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        minusButton.tintColor = .secondaryLabel
        // Encode exercise ID + set index
        minusButton.accessibilityIdentifier = "minus_\(exercise.id.uuidString)_\(setIndex)"
        minusButton.addTarget(self, action: #selector(setMinusTapped(_:)), for: .touchUpInside)

        let weightLabel = UILabel()
        weightLabel.translatesAutoresizingMaskIntoConstraints = false
        weightLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        weightLabel.textColor = .label
        weightLabel.textAlignment = .center
        weightLabel.text = displayWeight(weight, for: exercise)
        weightLabel.tag = 200 + setIndex // tag for updating

        let plusButton = UIButton(type: .system)
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        plusButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        plusButton.tintColor = .secondaryLabel
        plusButton.accessibilityIdentifier = "plus_\(exercise.id.uuidString)_\(setIndex)"
        plusButton.addTarget(self, action: #selector(setPlusTapped(_:)), for: .touchUpInside)

        // Per-set PR trophy (hidden by default, shown on the set that hit the PR)
        let prTrophy = UIImageView(image: UIImage(systemName: "trophy.fill"))
        prTrophy.translatesAutoresizingMaskIntoConstraints = false
        prTrophy.tintColor = .systemYellow
        prTrophy.contentMode = .scaleAspectFit
        prTrophy.isHidden = true
        prTrophy.tag = Self.prTrophyTagBase + setIndex

        // Delete set button
        let deleteButton = UIButton(type: .system)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        let deleteConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        deleteButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: deleteConfig), for: .normal)
        deleteButton.tintColor = .tertiaryLabel
        deleteButton.accessibilityIdentifier = "delete_\(exercise.id.uuidString)_\(setIndex)"
        deleteButton.accessibilityLabel = "Delete set \(setIndex + 1)"
        deleteButton.addTarget(self, action: #selector(deleteSetTapped(_:)), for: .touchUpInside)

        container.addSubview(setLabel)
        container.addSubview(minusButton)
        container.addSubview(weightLabel)
        container.addSubview(plusButton)
        container.addSubview(prTrophy)
        container.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 32),

            setLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 64),
            setLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            setLabel.widthAnchor.constraint(equalToConstant: 40),

            minusButton.leadingAnchor.constraint(equalTo: setLabel.trailingAnchor, constant: 8),
            minusButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            minusButton.widthAnchor.constraint(equalToConstant: 24),
            minusButton.heightAnchor.constraint(equalToConstant: 24),

            weightLabel.leadingAnchor.constraint(equalTo: minusButton.trailingAnchor, constant: 4),
            weightLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            weightLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),

            plusButton.leadingAnchor.constraint(equalTo: weightLabel.trailingAnchor, constant: 4),
            plusButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            plusButton.widthAnchor.constraint(equalToConstant: 24),
            plusButton.heightAnchor.constraint(equalToConstant: 24),

            prTrophy.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 6),
            prTrophy.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            prTrophy.widthAnchor.constraint(equalToConstant: 14),
            prTrophy.heightAnchor.constraint(equalToConstant: 14),

            deleteButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        return container
    }

    // MARK: - Add Set Button

    private func createAddSetButton(exercise: WorkoutTemplate.Exercise) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("+ Add Set", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        button.tintColor = .systemBlue
        button.accessibilityIdentifier = "addset_\(exercise.id.uuidString)"
        button.addTarget(self, action: #selector(addSetTapped(_:)), for: .touchUpInside)

        container.addSubview(button)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 32),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 64),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    // MARK: - Actions

    @objc private func longPressCellHandler(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        HapticManager.shared.medium()
        delegate?.scheduleWorkoutCellDidLongPress(self)
    }

    @objc private func startButtonTapped() {
        guard let workout else { return }
        HapticManager.shared.medium()
        delegate?.scheduleWorkoutCellDidTapStartWorkout(self, workout: workout)
    }

    @objc private func exerciseButtonTapped(_ sender: UIButton) {
        guard let workout = workout,
              let idString = sender.accessibilityIdentifier,
              idString.hasPrefix("exercise_"),
              let exerciseId = UUID(uuidString: String(idString.dropFirst("exercise_".count))) else { return }
        for exercise in workout.exercises where exercise.id == exerciseId {
            let wasCompleted = exerciseCompletions[exercise.id] ?? false
            wasCompleted ? HapticManager.shared.light() : HapticManager.shared.success()
            delegate?.scheduleWorkoutCell(self, didToggleExercise: exercise, in: workout)
            return
        }
    }

    @objc private func exerciseTimerTapped(_ sender: UIButton) {
        guard let workout = workout,
              let idString = sender.accessibilityIdentifier,
              idString.hasPrefix("timer_"),
              let exerciseId = UUID(uuidString: String(idString.dropFirst("timer_".count))) else { return }
        for exercise in workout.exercises where exercise.id == exerciseId {
            HapticManager.shared.medium()
            delegate?.scheduleWorkoutCell(self, didTapTimerForExercise: exercise, in: workout)
            return
        }
    }

    @objc private func exerciseRowTapped(_ gesture: UITapGestureRecognizer) {
        guard let workout = workout,
              let container = gesture.view,
              let exerciseIdString = container.accessibilityIdentifier,
              let exerciseId = UUID(uuidString: exerciseIdString) else { return }

        for exercise in workout.exercises where exercise.id == exerciseId {
            let wasCompleted = exerciseCompletions[exercise.id] ?? false
            wasCompleted ? HapticManager.shared.light() : HapticManager.shared.success()
            delegate?.scheduleWorkoutCell(self, didToggleExercise: exercise, in: workout)
            return
        }
    }

    @objc private func summaryRowTapped(_ gesture: UITapGestureRecognizer) {
        guard let container = gesture.view,
              let idString = container.accessibilityIdentifier,
              idString.hasPrefix("summary_"),
              let exerciseId = UUID(uuidString: String(idString.dropFirst("summary_".count))) else { return }

        HapticManager.shared.selection()
        toggleExpand(exerciseId: exerciseId)
    }

    private func toggleExpand(exerciseId: UUID) {
        let isNowExpanded: Bool
        if expandedExercises.contains(exerciseId) {
            expandedExercises.remove(exerciseId)
            isNowExpanded = false
        } else {
            expandedExercises.insert(exerciseId)
            isNowExpanded = true
        }

        // Find the sets container and summary row for this exercise
        guard let setsContainer = setRowStacks[exerciseId] else { return }

        // Find the summary row's chevron in the parent
        let parentStack = setsContainer.superview as? UIStackView
        let summaryRow = parentStack?.arrangedSubviews.first { view in
            guard let id = view.accessibilityIdentifier else { return false }
            return id == "summary_\(exerciseId.uuidString)"
        }

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            setsContainer.isHidden = !isNowExpanded
            setsContainer.alpha = isNowExpanded ? 1 : 0

            // Update chevron
            if let chevronView = summaryRow?.viewWithTag(100) as? UIImageView {
                let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                chevronView.image = UIImage(systemName: isNowExpanded ? "chevron.down" : "chevron.right", withConfiguration: config)
            }

            self.contentView.layoutIfNeeded()
        }

        delegate?.scheduleWorkoutCellDidToggleExpand(self, exerciseId: exerciseId)
        delegate?.scheduleWorkoutCellNeedsResize(self)
    }

    @objc private func setMinusTapped(_ sender: UIButton) {
        guard let parts = parseSetButtonId(sender.accessibilityIdentifier, prefix: "minus_"),
              var weights = editingSetWeights[parts.exerciseId],
              let exercise = workout?.exercises.first(where: { $0.id == parts.exerciseId }) else { return }

        if let machineId = exercise.machineId,
           let machine = MachineStore.shared.machine(for: machineId) {
            weights[parts.setIndex] = machine.incrementDown(from: weights[parts.setIndex])
        } else {
            let increment = weightLogStore.preferredUnit.increment
            weights[parts.setIndex] = max(0, weights[parts.setIndex] - increment)
        }
        editingSetWeights[parts.exerciseId] = weights
        HapticManager.shared.light()

        updateSetWeightLabel(sender: sender, weight: weights[parts.setIndex], exercise: exercise)
        updateSummaryLabel(exercise: exercise, weights: weights)
    }

    @objc private func setPlusTapped(_ sender: UIButton) {
        guard let parts = parseSetButtonId(sender.accessibilityIdentifier, prefix: "plus_"),
              var weights = editingSetWeights[parts.exerciseId],
              let exercise = workout?.exercises.first(where: { $0.id == parts.exerciseId }) else { return }

        if let machineId = exercise.machineId,
           let machine = MachineStore.shared.machine(for: machineId) {
            weights[parts.setIndex] = machine.incrementUp(from: weights[parts.setIndex])
        } else {
            let increment = weightLogStore.preferredUnit.increment
            weights[parts.setIndex] += increment
        }
        editingSetWeights[parts.exerciseId] = weights
        HapticManager.shared.light()

        updateSetWeightLabel(sender: sender, weight: weights[parts.setIndex], exercise: exercise)
        updateSummaryLabel(exercise: exercise, weights: weights)
    }

    @objc private func addSetTapped(_ sender: UIButton) {
        guard let idString = sender.accessibilityIdentifier,
              idString.hasPrefix("addset_"),
              let exerciseId = UUID(uuidString: String(idString.dropFirst("addset_".count))),
              var weights = editingSetWeights[exerciseId],
              let workout = workout,
              let exercise = workout.exercises.first(where: { $0.id == exerciseId }),
              let setsContainer = setRowStacks[exerciseId] else { return }

        let lastWeight = weights.last ?? 0
        weights.append(lastWeight)
        editingSetWeights[exerciseId] = weights
        HapticManager.shared.light()

        let newIndex = weights.count - 1
        let setRow = createSetRow(exercise: exercise, setIndex: newIndex, weight: lastWeight)

        // Insert before the "+ Add Set" button (last arranged subview)
        let addSetButtonIndex = setsContainer.arrangedSubviews.count - 1
        setsContainer.insertArrangedSubview(setRow, at: addSetButtonIndex)

        updateSummaryLabel(exercise: exercise, weights: weights)
        delegate?.scheduleWorkoutCellNeedsResize(self)
    }

    @objc private func deleteSetTapped(_ sender: UIButton) {
        guard let parts = parseSetButtonId(sender.accessibilityIdentifier, prefix: "delete_"),
              var weights = editingSetWeights[parts.exerciseId],
              weights.count > 1,
              parts.setIndex < weights.count,
              let workout = workout,
              let exercise = workout.exercises.first(where: { $0.id == parts.exerciseId }),
              let setsContainer = setRowStacks[parts.exerciseId] else { return }

        // Remove the weight at this index
        weights.remove(at: parts.setIndex)
        editingSetWeights[parts.exerciseId] = weights
        HapticManager.shared.light()

        // Rebuild all set rows (indices shift after deletion)
        // Keep only the "+ Add Set" button (last arranged subview)
        let addSetView = setsContainer.arrangedSubviews.last
        for view in setsContainer.arrangedSubviews {
            if view !== addSetView {
                view.removeFromSuperview()
            }
        }

        // Re-add set rows with correct indices
        for i in 0..<weights.count {
            let setRow = createSetRow(exercise: exercise, setIndex: i, weight: weights[i])
            setsContainer.insertArrangedSubview(setRow, at: i)
        }

        updateSummaryLabel(exercise: exercise, weights: weights)
        delegate?.scheduleWorkoutCellNeedsResize(self)
    }

    @objc private func confirmSetsTapped(_ sender: UIButton) {
        guard let idString = sender.accessibilityIdentifier,
              idString.hasPrefix("confirm_"),
              let exerciseId = UUID(uuidString: String(idString.dropFirst("confirm_".count))),
              let workout = workout,
              let exercise = workout.exercises.first(where: { $0.id == exerciseId }),
              let weights = editingSetWeights[exerciseId] else { return }

        let wasModified = weights != (initialSetWeights[exerciseId] ?? [])

        let isPR = delegate?.scheduleWorkoutCell(self, didConfirmSetWeights: weights, wasModified: wasModified, for: exercise, in: workout) ?? false
        isPR ? HapticManager.shared.celebration() : HapticManager.shared.success()

        // Update confirm button visual
        sender.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
        sender.tintColor = .systemGreen

        // Update PR badge visibility in summary row
        if let summaryRow = sender.superview {
            // Find the PR badge (the last subview that isn't chevron/label/button)
            for subview in summaryRow.subviews {
                if subview.backgroundColor != nil && subview != sender {
                    subview.isHidden = !isPR
                }
            }
        }

        // Show per-set PR trophies on the best-weight set(s) for this exercise
        updateSetPRIndicators(containerKey: exerciseId, exerciseId: exercise.exerciseId, weights: weights, isPR: isPR)

        // Auto-collapse after confirming
        if expandedExercises.contains(exerciseId) {
            toggleExpand(exerciseId: exerciseId)
        }

        // Update initial weights to current (so re-confirming without changes shows wasModified=false)
        initialSetWeights[exerciseId] = weights
    }

    // MARK: - Helpers

    private struct SetButtonParts {
        let exerciseId: UUID
        let setIndex: Int
    }

    private func parseSetButtonId(_ identifier: String?, prefix: String) -> SetButtonParts? {
        guard let idString = identifier,
              idString.hasPrefix(prefix) else { return nil }

        let remainder = String(idString.dropFirst(prefix.count))
        let components = remainder.split(separator: "_")
        guard components.count == 2,
              let exerciseId = UUID(uuidString: String(components[0])),
              let setIndex = Int(components[1]) else { return nil }

        return SetButtonParts(exerciseId: exerciseId, setIndex: setIndex)
    }

    private func updateSetWeightLabel(sender: UIButton, weight: Double, exercise: WorkoutTemplate.Exercise?) {
        // The weight label is a sibling of the button in the same container
        guard let container = sender.superview else { return }
        for subview in container.subviews {
            if let label = subview as? UILabel, label.font == .monospacedDigitSystemFont(ofSize: 14, weight: .semibold) {
                if let exercise {
                    label.text = displayWeight(weight, for: exercise)
                } else {
                    label.text = weightLogStore.displayWeight(weight, for: UUID(), unit: weightLogStore.preferredUnit)
                }
                break
            }
        }
    }

    /// Show/hide per-set PR trophies. When isPR is true, the trophy appears on every set whose weight equals the best.
    /// - Parameters:
    ///   - containerKey: the exercise.id used as the key in setRowStacks
    ///   - exerciseId: the exercise.exerciseId (library ID) used for assisted-aware PR comparison
    private func updateSetPRIndicators(containerKey: UUID, exerciseId: UUID, weights: [Double], isPR: Bool) {
        guard let setsContainer = setRowStacks[containerKey] else { return }
        let bestWeight = weightLogStore.bestWeight(from: weights, for: exerciseId)

        for (index, view) in setsContainer.arrangedSubviews.enumerated() {
            guard index < weights.count else { break }
            if let trophy = view.viewWithTag(Self.prTrophyTagBase + index) as? UIImageView {
                trophy.isHidden = !(isPR && weights[index] == bestWeight)
            }
        }
    }

    private func updateSummaryLabel(exercise: WorkoutTemplate.Exercise, weights: [Double]) {
        // Find the summary row for this exercise and update the label
        guard let setsContainer = setRowStacks[exercise.id],
              let sectionStack = setsContainer.superview as? UIStackView else { return }

        for view in sectionStack.arrangedSubviews {
            if view.accessibilityIdentifier == "summary_\(exercise.id.uuidString)",
               let label = view.viewWithTag(101) as? UILabel {
                label.text = weightSummaryText(for: weights, exercise: exercise)
                break
            }
        }
    }

    func rectForExercise(exerciseId: UUID) -> CGRect? {
        guard let container = exerciseContainers[exerciseId] else { return nil }
        return contentView.convert(container.bounds, from: container)
    }
}
