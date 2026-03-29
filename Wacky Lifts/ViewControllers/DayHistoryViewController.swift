import UIKit

final class DayHistoryViewController: UIViewController {

    private let date: Date
    private let streakStore = StreakStore.shared
    private let completionStore = CompletionStore.shared
    private let libraryStore = WorkoutLibraryStore.shared
    private let weightLogStore = WeightLogStore.shared
    private let snapshotStore = WorkoutSnapshotStore.shared

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    init(date: Date) {
        self.date = date
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigation()
        setupScrollView()
        setupContent()
    }

    private func setupNavigation() {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        title = formatter.string(from: date)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])
    }

    private func setupContent() {
        let hasActivity = streakStore.hasActivity(on: date)
        let hasCompletedWorkout = streakStore.hasCompletedWorkout(on: date)
        let weightLogs = weightLogStore.logs(on: date)
        let hasPR = weightLogStore.hasPR(on: date)

        // Status card
        let statusCard = makeStatusCard(hasActivity: hasActivity, hasCompletedWorkout: hasCompletedWorkout, hasPR: hasPR)
        contentStack.addArrangedSubview(statusCard)

        // Weight logs section (if any)
        if !weightLogs.isEmpty {
            let logsHeader = UILabel()
            logsHeader.text = "Weight Log"
            logsHeader.font = .preferredFont(forTextStyle: .headline)
            logsHeader.textColor = .label
            contentStack.addArrangedSubview(logsHeader)

            let logsCard = makeWeightLogsCard(logs: weightLogs)
            contentStack.addArrangedSubview(logsCard)
        }

        // Workout details (merge completion store + weight log workout IDs for past weeks
        // where completion data may have been cleaned up)
        var workoutIds = completionStore.workoutIdsWithCompletions(on: date)
        for log in weightLogs {
            workoutIds.insert(log.workoutId)
        }

        if workoutIds.isEmpty && weightLogs.isEmpty {
            let noDataLabel = UILabel()
            noDataLabel.text = "No detailed workout data available for this day."
            noDataLabel.font = .preferredFont(forTextStyle: .body)
            noDataLabel.textColor = .secondaryLabel
            noDataLabel.textAlignment = .center
            noDataLabel.numberOfLines = 0
            contentStack.addArrangedSubview(noDataLabel)
        } else if !workoutIds.isEmpty {
            let workoutsHeader = UILabel()
            workoutsHeader.text = "Workouts"
            workoutsHeader.font = .preferredFont(forTextStyle: .headline)
            workoutsHeader.textColor = .label
            contentStack.addArrangedSubview(workoutsHeader)

            for workoutId in workoutIds {
                let workoutCard = makeWorkoutCard(for: workoutId)
                contentStack.addArrangedSubview(workoutCard)
            }
        }
    }

    private func makeStatusCard(hasActivity: Bool, hasCompletedWorkout: Bool, hasPR: Bool) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        let statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .headline)

        let descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .preferredFont(forTextStyle: .subheadline)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0

        // PR badge (shown if PR was hit)
        let prBadge = UIImageView(image: UIImage(systemName: "trophy.fill"))
        prBadge.translatesAutoresizingMaskIntoConstraints = false
        prBadge.tintColor = .systemYellow
        prBadge.contentMode = .scaleAspectFit
        prBadge.isHidden = !hasPR

        if hasCompletedWorkout {
            iconView.image = UIImage(systemName: "checkmark.circle.fill")
            iconView.tintColor = .systemGreen
            statusLabel.text = hasPR ? "Workout Completed 🏆" : "Workout Completed"
            statusLabel.textColor = .systemGreen
            descriptionLabel.text = hasPR
                ? "You completed a workout and hit a PR!"
                : "You completed at least one full workout on this day."
        } else if hasActivity {
            iconView.image = UIImage(systemName: "figure.strengthtraining.traditional")
            iconView.tintColor = .systemBlue
            statusLabel.text = hasPR ? "Exercise Activity 🏆" : "Exercise Activity"
            statusLabel.textColor = .label
            descriptionLabel.text = hasPR
                ? "You completed some exercises and hit a PR!"
                : "You completed some exercises on this day."
        } else if hasPR {
            // PR day without current activity data (old PR)
            iconView.image = UIImage(systemName: "trophy.fill")
            iconView.tintColor = .systemYellow
            statusLabel.text = "Personal Record Day"
            statusLabel.textColor = .systemYellow
            descriptionLabel.text = "You hit a personal record on this day."
        } else {
            iconView.image = UIImage(systemName: "moon.zzz.fill")
            iconView.tintColor = .secondaryLabel
            statusLabel.text = "Rest Day"
            statusLabel.textColor = .secondaryLabel
            descriptionLabel.text = "No workout activity recorded."
        }

        card.addSubview(iconView)
        card.addSubview(statusLabel)
        card.addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            statusLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            descriptionLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        return card
    }

    private func makeWorkoutCard(for workoutId: UUID) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.textColor = .label

        let detailLabel = UILabel()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel

        // Try to get workout details from snapshot first, then library
        let completionCount = completionStore.completedExerciseCount(for: workoutId, on: date)
        let logCount = weightLogStore.logs(on: date).filter { $0.workoutId == workoutId }.count
        let exerciseCount = max(completionCount, logCount)

        if let workout = snapshotStore.snapshot(for: workoutId, on: date) ?? libraryStore.template(withId: workoutId) {
            nameLabel.text = workout.name
            let totalCount = workout.exercises.count
            detailLabel.text = "\(exerciseCount)/\(totalCount) exercises completed"
        } else {
            nameLabel.text = "Workout"
            detailLabel.text = "\(exerciseCount) exercises completed"
        }

        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.tintColor = .systemGreen
        checkmark.contentMode = .scaleAspectFit

        card.addSubview(nameLabel)
        card.addSubview(detailLabel)
        card.addSubview(checkmark)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: checkmark.leadingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            checkmark.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            checkmark.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24),
        ])

        return card
    }

    private func makeWeightLogsCard(logs: [ExerciseLog]) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])

        for (index, log) in logs.enumerated() {
            let row = makeLogRow(log: log)
            stack.addArrangedSubview(row)

            // Add separator except for last item
            if index < logs.count - 1 {
                let separator = UIView()
                separator.backgroundColor = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(separator)
                separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                separator.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 16).isActive = true
                separator.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -16).isActive = true
            }
        }

        return card
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
    }

    /// Build an attributed string for the set progression, highlighting the PR set(s) in gold.
    private func weightProgressionText(for log: ExerciseLog) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let normalColor = UIColor.secondaryLabel
        let prColor = UIColor.systemYellow

        guard let setWeights = log.setWeights, !setWeights.isEmpty else {
            // Legacy single-weight log
            let text = "\(formatWeight(log.weight)) \(log.unit.symbol)"
            let color = (log.isPersonalRecord && log.weight > 0) ? prColor : normalColor
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }

        let maxWeight = setWeights.max() ?? 0
        let allSame = Set(setWeights).count == 1
        let result = NSMutableAttributedString()

        if allSame {
            // "3 × 135 lbs"
            let prefix = "\(setWeights.count) × "
            result.append(NSAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: normalColor]))

            let weightStr = formatWeight(setWeights[0])
            let weightColor = (log.isPersonalRecord && setWeights[0] == maxWeight) ? prColor : normalColor
            result.append(NSAttributedString(string: weightStr, attributes: [.font: font, .foregroundColor: weightColor]))

            result.append(NSAttributedString(string: " \(log.unit.symbol)", attributes: [.font: font, .foregroundColor: normalColor]))
        } else {
            // "135 → 145 → 155 lbs"
            for (i, w) in setWeights.enumerated() {
                if i > 0 {
                    result.append(NSAttributedString(string: " → ", attributes: [.font: font, .foregroundColor: normalColor]))
                }
                let weightStr = formatWeight(w)
                let weightColor = (log.isPersonalRecord && w == maxWeight) ? prColor : normalColor
                result.append(NSAttributedString(string: weightStr, attributes: [.font: font, .foregroundColor: weightColor]))
            }
            result.append(NSAttributedString(string: " \(log.unit.symbol)", attributes: [.font: font, .foregroundColor: normalColor]))
        }

        return result
    }

    private func makeLogRow(log: ExerciseLog) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .preferredFont(forTextStyle: .subheadline)
        nameLabel.textColor = .label
        if let snapshot = snapshotStore.snapshot(for: log.workoutId, on: date),
           let ex = snapshot.exercises.first(where: { $0.id == log.entryId }) {
            nameLabel.text = "\(log.exerciseName) — \(ex.detailSummary)"
        } else {
            nameLabel.text = log.exerciseName
        }

        let weightLabel = UILabel()
        weightLabel.translatesAutoresizingMaskIntoConstraints = false
        weightLabel.attributedText = weightProgressionText(for: log)

        let prBadge = UIImageView(image: UIImage(systemName: "trophy.fill"))
        prBadge.translatesAutoresizingMaskIntoConstraints = false
        prBadge.tintColor = .systemYellow
        prBadge.contentMode = .scaleAspectFit
        prBadge.isHidden = !log.isPersonalRecord

        container.addSubview(nameLabel)
        container.addSubview(weightLabel)
        container.addSubview(prBadge)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: prBadge.leadingAnchor, constant: -8),

            weightLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            weightLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            weightLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            weightLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            prBadge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            prBadge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            prBadge.widthAnchor.constraint(equalToConstant: 20),
            prBadge.heightAnchor.constraint(equalToConstant: 20),
        ])

        return container
    }
}
