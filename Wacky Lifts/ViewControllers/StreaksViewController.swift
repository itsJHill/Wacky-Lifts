@preconcurrency import UIKit

final class StreaksViewController: UIViewController {

    private let streakStore = StreakStore.shared
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let streakCard = StatCardView()
    private let longestStreakCard = StatCardView()
    private let workoutsCard = StatCardView()
    private let exercisesCard = StatCardView()
    private var exercisesMode: ActiveDaysMode = .month
    private let activeDaysCard = StatCardView()
    private enum ActiveDaysMode: Int, CaseIterable {
        case month, year, allTime
    }
    private var activeDaysMode: ActiveDaysMode = .month
    private let messageLabel = UILabel()

    private let weightLogStore = WeightLogStore.shared

    private let prContainer = UIView()
    private let prStackView = UIStackView()

    private let historyHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "History"
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
        label.font = UIFont.systemFont(ofSize: descriptor.pointSize, weight: .bold)
        label.textColor = .label
        return label
    }()

    private let calendarView = HistoryCalendarView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Streaks"
        view.backgroundColor = .systemBackground

        setupScrollView()
        setupCards()
        updateStats()
        observeChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    private func setupCards() {
        // Main streak card (featured)
        streakCard.configure(
            icon: "flame.fill",
            iconColor: .systemOrange,
            title: "Current Streak",
            value: "0",
            subtitle: "days",
            isFeatured: true
        )
        contentStack.addArrangedSubview(streakCard)

        // Stats grid
        let gridStack = UIStackView()
        gridStack.axis = .horizontal
        gridStack.spacing = 12
        gridStack.distribution = .fillEqually

        longestStreakCard.configure(
            icon: "trophy.fill",
            iconColor: .systemYellow,
            title: "Longest Streak",
            value: "0",
            subtitle: "days",
            isFeatured: false
        )

        activeDaysCard.configure(
            icon: "calendar",
            iconColor: .systemBlue,
            title: "Active Days",
            value: "0",
            subtitle: "this month",
            isFeatured: false
        )

        let activeDaysTap = UITapGestureRecognizer(target: self, action: #selector(activeDaysCardTapped))
        activeDaysCard.addGestureRecognizer(activeDaysTap)

        gridStack.addArrangedSubview(longestStreakCard)
        gridStack.addArrangedSubview(activeDaysCard)
        contentStack.addArrangedSubview(gridStack)

        // Second row
        let gridStack2 = UIStackView()
        gridStack2.axis = .horizontal
        gridStack2.spacing = 12
        gridStack2.distribution = .fillEqually

        workoutsCard.configure(
            icon: "checkmark.circle.fill",
            iconColor: .systemGreen,
            title: "Workouts",
            value: "0",
            subtitle: "completed",
            isFeatured: false
        )

        exercisesCard.configure(
            icon: "figure.strengthtraining.traditional",
            iconColor: .systemPurple,
            title: "Exercises",
            value: "0",
            subtitle: "this month",
            isFeatured: false
        )

        let exercisesTap = UITapGestureRecognizer(target: self, action: #selector(exercisesCardTapped))
        exercisesCard.addGestureRecognizer(exercisesTap)

        gridStack2.addArrangedSubview(workoutsCard)
        gridStack2.addArrangedSubview(exercisesCard)
        contentStack.addArrangedSubview(gridStack2)

        // Motivational message
        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        contentStack.addArrangedSubview(messageLabel)

        contentStack.setCustomSpacing(24, after: gridStack2)

        // Recent PRs section
        contentStack.setCustomSpacing(32, after: messageLabel)

        // Card-style container matching the stat cards
        prContainer.translatesAutoresizingMaskIntoConstraints = false
        prContainer.layer.cornerRadius = 16
        prContainer.clipsToBounds = false
        prContainer.layer.shadowColor = UIColor.black.cgColor
        prContainer.layer.shadowOpacity = 0.12
        prContainer.layer.shadowRadius = 10
        prContainer.layer.shadowOffset = CGSize(width: 0, height: 4)

        let prBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        prBlur.translatesAutoresizingMaskIntoConstraints = false
        prBlur.layer.cornerRadius = 16
        prBlur.clipsToBounds = true
        prContainer.addSubview(prBlur)

        let prBackground = UIView()
        prBackground.backgroundColor = .secondarySystemBackground
        prBackground.translatesAutoresizingMaskIntoConstraints = false
        prBackground.layer.cornerRadius = 16
        prBackground.clipsToBounds = true
        prContainer.addSubview(prBackground)

        // Header inside the card
        let prCardHeader = UIStackView()
        prCardHeader.axis = .horizontal
        prCardHeader.spacing = 8
        prCardHeader.alignment = .center
        prCardHeader.translatesAutoresizingMaskIntoConstraints = false

        let prIcon = UIImageView(image: UIImage(systemName: "trophy.fill"))
        prIcon.tintColor = .systemYellow
        prIcon.translatesAutoresizingMaskIntoConstraints = false
        prIcon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            prIcon.widthAnchor.constraint(equalToConstant: 24),
            prIcon.heightAnchor.constraint(equalToConstant: 24),
        ])

        let prTitleLabel = UILabel()
        prTitleLabel.text = "Recent PRs"
        prTitleLabel.font = .preferredFont(forTextStyle: .caption1)
        prTitleLabel.textColor = .secondaryLabel

        prCardHeader.addArrangedSubview(prIcon)
        prCardHeader.addArrangedSubview(prTitleLabel)

        prContainer.addSubview(prCardHeader)

        prStackView.axis = .vertical
        prStackView.spacing = 0
        prStackView.translatesAutoresizingMaskIntoConstraints = false
        prContainer.addSubview(prStackView)

        NSLayoutConstraint.activate([
            prBlur.topAnchor.constraint(equalTo: prContainer.topAnchor),
            prBlur.leadingAnchor.constraint(equalTo: prContainer.leadingAnchor),
            prBlur.trailingAnchor.constraint(equalTo: prContainer.trailingAnchor),
            prBlur.bottomAnchor.constraint(equalTo: prContainer.bottomAnchor),

            prBackground.topAnchor.constraint(equalTo: prContainer.topAnchor),
            prBackground.leadingAnchor.constraint(equalTo: prContainer.leadingAnchor),
            prBackground.trailingAnchor.constraint(equalTo: prContainer.trailingAnchor),
            prBackground.bottomAnchor.constraint(equalTo: prContainer.bottomAnchor),

            prCardHeader.topAnchor.constraint(equalTo: prContainer.topAnchor, constant: 16),
            prCardHeader.leadingAnchor.constraint(equalTo: prContainer.leadingAnchor, constant: 16),
            prCardHeader.trailingAnchor.constraint(lessThanOrEqualTo: prContainer.trailingAnchor, constant: -16),

            prStackView.topAnchor.constraint(equalTo: prCardHeader.bottomAnchor, constant: 12),
            prStackView.leadingAnchor.constraint(equalTo: prContainer.leadingAnchor),
            prStackView.trailingAnchor.constraint(equalTo: prContainer.trailingAnchor),
            prStackView.bottomAnchor.constraint(equalTo: prContainer.bottomAnchor),
        ])

        contentStack.addArrangedSubview(prContainer)
        updatePRPanel()

        // History section
        contentStack.setCustomSpacing(32, after: prContainer)
        contentStack.addArrangedSubview(historyHeaderLabel)

        calendarView.delegate = self
        contentStack.addArrangedSubview(calendarView)
    }

    private func updateStats() {
        let unitName = streakStore.streakUnitName
        let currentStreak = streakStore.currentStreak

        streakCard.updateValue("\(currentStreak)")
        streakCard.updateSubtitle(unitName)
        updateStreakHeat(for: currentStreak)

        longestStreakCard.updateValue("\(streakStore.longestStreak)")
        longestStreakCard.updateSubtitle(unitName)

        // Show weekly progress when in perWeek mode
        if streakStore.streakMode == .perWeek {
            let current = streakStore.currentWeekWorkoutCount
            let goal = streakStore.weeklyWorkoutGoal
            workoutsCard.updateValue("\(current)/\(goal)")
            workoutsCard.updateSubtitle("this week")
        } else {
            workoutsCard.updateValue("\(streakStore.totalCompletedWorkouts)")
            workoutsCard.updateSubtitle("completed")
        }

        switch exercisesMode {
        case .month:
            exercisesCard.updateValue("\(streakStore.completedExercisesThisMonth)")
            exercisesCard.updateSubtitle("this month")
        case .year:
            exercisesCard.updateValue("\(streakStore.completedExercisesThisYear)")
            exercisesCard.updateSubtitle("this year")
        case .allTime:
            exercisesCard.updateValue("\(streakStore.totalCompletedExercises)")
            exercisesCard.updateSubtitle("all time")
        }

        switch activeDaysMode {
        case .month:
            activeDaysCard.updateValue("\(streakStore.activeDaysThisMonth)")
            activeDaysCard.updateSubtitle("this month")
        case .year:
            activeDaysCard.updateValue("\(streakStore.activeDaysThisYear)")
            activeDaysCard.updateSubtitle("this year")
        case .allTime:
            activeDaysCard.updateValue("\(streakStore.totalActiveDays)")
            activeDaysCard.updateSubtitle("all time")
        }

        // Update motivational message based on mode
        messageLabel.text = streakStore.streakDescription + " to keep your streak going!"
    }

    private func updateStreakHeat(for streak: Int) {
        if streak <= 0 {
            streakCard.updateAccentColor(.systemOrange, backgroundColor: .secondarySystemBackground)
            return
        }
        let heat = min(1, CGFloat(streak) / 30.0)
        let start = UIColor.systemOrange.resolvedColor(with: view.traitCollection)
        let end = UIColor.systemRed.resolvedColor(with: view.traitCollection)
        let accent = blendColor(from: start, to: end, t: heat)
        let backgroundAlpha = 0.12 + (0.2 * heat)
        let background = accent.withAlphaComponent(backgroundAlpha)
        streakCard.updateAccentColor(accent, backgroundColor: background)
    }

    private func blendColor(from: UIColor, to: UIColor, t: CGFloat) -> UIColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }

    private func updatePRPanel() {
        prStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let prs = weightLogStore.allPersonalRecords()
        let previewCount = min(prs.count, 3)

        if prs.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No personal records yet"
            emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
            emptyLabel.textColor = .tertiaryLabel
            emptyLabel.textAlignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            let wrapper = UIView()
            wrapper.addSubview(emptyLabel)
            NSLayoutConstraint.activate([
                emptyLabel.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 20),
                emptyLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -20),
                emptyLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
                emptyLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            ])
            prStackView.addArrangedSubview(wrapper)
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        for (index, pr) in prs.prefix(previewCount).enumerated() {
            let row = makePRRow(
                name: pr.exerciseName,
                weight: pr.weight,
                unit: pr.unit,
                date: dateFormatter.string(from: pr.date)
            )
            prStackView.addArrangedSubview(row)

            if index < previewCount - 1 {
                let separator = UIView()
                separator.backgroundColor = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: 1.0 / (view.window?.windowScene?.screen.scale ?? 3.0)).isActive = true
                let wrapper = UIView()
                wrapper.addSubview(separator)
                separator.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    separator.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
                    separator.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
                    separator.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    separator.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                ])
                prStackView.addArrangedSubview(wrapper)
            }
        }

        // "See All" row if more than 3 PRs
        if prs.count > previewCount {
            let topSep = UIView()
            topSep.backgroundColor = .separator
            topSep.translatesAutoresizingMaskIntoConstraints = false
            topSep.heightAnchor.constraint(equalToConstant: 1.0 / (view.window?.windowScene?.screen.scale ?? 3.0)).isActive = true
            let sepWrapper = UIView()
            sepWrapper.addSubview(topSep)
            NSLayoutConstraint.activate([
                topSep.leadingAnchor.constraint(equalTo: sepWrapper.leadingAnchor, constant: 16),
                topSep.trailingAnchor.constraint(equalTo: sepWrapper.trailingAnchor, constant: -16),
                topSep.topAnchor.constraint(equalTo: sepWrapper.topAnchor),
                topSep.bottomAnchor.constraint(equalTo: sepWrapper.bottomAnchor),
            ])
            prStackView.addArrangedSubview(sepWrapper)

            let seeAllRow = UIView()
            let seeAllLabel = UILabel()
            seeAllLabel.text = "See All"
            seeAllLabel.font = .preferredFont(forTextStyle: .subheadline)
            seeAllLabel.textColor = .systemBlue
            seeAllLabel.translatesAutoresizingMaskIntoConstraints = false

            let countLabel = UILabel()
            countLabel.text = "\(prs.count)"
            countLabel.font = .preferredFont(forTextStyle: .subheadline)
            countLabel.textColor = .tertiaryLabel
            countLabel.translatesAutoresizingMaskIntoConstraints = false

            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = .tertiaryLabel
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.contentMode = .scaleAspectFit
            chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                pointSize: 12, weight: .semibold)

            seeAllRow.addSubview(seeAllLabel)
            seeAllRow.addSubview(countLabel)
            seeAllRow.addSubview(chevron)

            NSLayoutConstraint.activate([
                seeAllLabel.leadingAnchor.constraint(equalTo: seeAllRow.leadingAnchor, constant: 16),
                seeAllLabel.topAnchor.constraint(equalTo: seeAllRow.topAnchor, constant: 12),
                seeAllLabel.bottomAnchor.constraint(equalTo: seeAllRow.bottomAnchor, constant: -12),

                chevron.trailingAnchor.constraint(equalTo: seeAllRow.trailingAnchor, constant: -16),
                chevron.centerYAnchor.constraint(equalTo: seeAllRow.centerYAnchor),

                countLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
                countLabel.centerYAnchor.constraint(equalTo: seeAllRow.centerYAnchor),
            ])

            let tap = UITapGestureRecognizer(target: self, action: #selector(seeAllPRsTapped))
            seeAllRow.addGestureRecognizer(tap)
            prStackView.addArrangedSubview(seeAllRow)
        }
    }

    private func makePRRow(name: String, weight: Double, unit: WeightUnit, date: String) -> UIView {
        let container = UIView()

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .preferredFont(forTextStyle: .subheadline)
        nameLabel.textColor = .label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let dateLabel = UILabel()
        dateLabel.text = date
        dateLabel.font = .preferredFont(forTextStyle: .caption2)
        dateLabel.textColor = .tertiaryLabel
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        // Weight badge on the right
        let weightText = weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)

        let badgeLabel = UILabel()
        badgeLabel.text = "\(weightText) \(unit.symbol)"
        badgeLabel.font = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .semibold)
        badgeLabel.textColor = .systemYellow
        badgeLabel.textAlignment = .right
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        container.addSubview(nameLabel)
        container.addSubview(dateLabel)
        container.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -12),

            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            dateLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            badgeLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            badgeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        return container
    }

    @objc private func seeAllPRsTapped() {
        let vc = AllPRsViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func observeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStreakChange),
            name: StreakStore.streakDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWeightLogChange),
            name: WeightLogStore.logsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCompletionChange),
            name: CompletionStore.completionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func exercisesCardTapped() {
        let all = ActiveDaysMode.allCases
        let next = (exercisesMode.rawValue + 1) % all.count
        exercisesMode = all[next]
        HapticManager.shared.selection()
        updateStats()
    }

    @objc private func activeDaysCardTapped() {
        let all = ActiveDaysMode.allCases
        let next = (activeDaysMode.rawValue + 1) % all.count
        activeDaysMode = all[next]
        HapticManager.shared.selection()
        updateStats()
    }

    @objc private func handleStreakChange() {
        updateStats()
        calendarView.refresh()
    }

    @objc private func handleWeightLogChange() {
        updatePRPanel()
        calendarView.refresh()
    }

    @objc private func handleCompletionChange() {
        updateStats()
        calendarView.refresh()
    }
}

// MARK: - HistoryCalendarViewDelegate

extension StreaksViewController: HistoryCalendarViewDelegate {
    func historyCalendarView(_ view: HistoryCalendarView, didSelectDate date: Date) {
        HapticManager.shared.selection()
        let detailVC = DayHistoryViewController(date: date)
        let nav = UINavigationController(rootViewController: detailVC)
        nav.modalPresentationStyle = .pageSheet

        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        present(nav, animated: true)
    }
}

// MARK: - Stat Card View

private final class StatCardView: UIView {

    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let backgroundView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        layer.cornerRadius = 16
        clipsToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = layer.cornerRadius
        blurView.clipsToBounds = true
        addSubview(blurView)

        backgroundView.backgroundColor = .secondarySystemBackground
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = layer.cornerRadius
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Use Dynamic Type with scaled metrics for accessibility
        let baseValueFont = UIFont.systemFont(ofSize: 34, weight: .bold)
        valueLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: baseValueFont)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .label
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .preferredFont(forTextStyle: .caption2)
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            valueLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            subtitleLabel.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 4),
            subtitleLabel.lastBaselineAnchor.constraint(equalTo: valueLabel.lastBaselineAnchor),

            bottomAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 16),
        ])
    }

    func configure(icon: String, iconColor: UIColor, title: String, value: String, subtitle: String, isFeatured: Bool) {
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.tintColor = iconColor
        titleLabel.text = title
        valueLabel.text = value
        subtitleLabel.text = subtitle

        if isFeatured {
            // Use Dynamic Type with scaled metrics for featured large value
            let baseFeaturedFont = UIFont.systemFont(ofSize: 56, weight: .bold)
            valueLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: baseFeaturedFont)

            NSLayoutConstraint.activate([
                iconImageView.widthAnchor.constraint(equalToConstant: 32),
                iconImageView.heightAnchor.constraint(equalToConstant: 32),
            ])
        }
    }

    func updateValue(_ value: String) {
        valueLabel.text = value
    }

    func updateSubtitle(_ subtitle: String) {
        subtitleLabel.text = subtitle
    }

    func updateAccentColor(_ color: UIColor, backgroundColor: UIColor) {
        iconImageView.tintColor = color
        backgroundView.backgroundColor = backgroundColor
    }
}
