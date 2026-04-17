@preconcurrency import UIKit

final class ScheduleViewController: UIViewController {

    private nonisolated enum Section: Hashable, Sendable {
        case main
    }

    private let profileStore = UserProfileStore.shared
    private let store = ScheduleStore.shared
    private let completionStore = CompletionStore.shared
    private let streakStore = StreakStore.shared
    private let weightLogStore = WeightLogStore.shared
    private let libraryStore = WorkoutLibraryStore.shared
    private let snapshotStore = WorkoutSnapshotStore.shared
    private let isoCalendar = Calendar(identifier: .iso8601)

    private var days: [WeekdayStripView.Day] = []
    private var weekdays: [Weekday] = [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
    ]
    private var selectedWeekday: Weekday = .monday
    private var selectedDate: Date = Date()

    private let headerLabel: UILabel = {
        let label = UILabel()
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
        label.font = UIFont.systemFont(ofSize: descriptor.pointSize, weight: .bold)
        label.textColor = .label
        label.isUserInteractionEnabled = true
        return label
    }()

    private var previousDayIndex: Int = 0
    private var hasScrolledToInitialDay = false
    private var hasShownGreeting = false
    private var greetingWorkItem: DispatchWorkItem?
    private var lastStreakValue: Int = 0
    private var streakCountTimer: Timer?

    private let streakBadge: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let streakIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "flame.fill"))
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let streakLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .systemOrange
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let addButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Add workout"
        button.accessibilityHint = "Add a workout to this day"
        return button
    }()

    private let weekStripView = WeekdayStripView()

    // MARK: - Paging

    private let pagingScrollView: PagingScrollView = {
        let sv = PagingScrollView()
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.bounces = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let pagingContentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var dayTableViews: [UITableView] = []
    private var dayDataSources: [UITableViewDiffableDataSource<Section, WorkoutTemplate>] = []
    private var expandedExercises: Set<UUID> = []
    private var pendingScrollToWorkoutId: UUID?
    private var pendingScrollToExerciseId: UUID?

    private let headerContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 20
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.layer.shadowRadius = 8
        container.layer.shadowOpacity = 0.08
        return container
    }()

    private let headerBlurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let headerBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private var headerHeightConstraint: NSLayoutConstraint?

    private let statusBarBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        configureDays()
        configureLayout()
        configureWeekStrip()
        configureTableViews()
        configureDataSources()
        applyAllSnapshots(animated: false)
        observeScheduleChanges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // Refresh from library in case workouts were edited while view was not visible
        store.refreshFromLibrary()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showGreetingIfNeeded()
    }

    private func selectDay(at index: Int) {
        guard index >= 0, index < weekdays.count, index < days.count else { return }
        guard index != previousDayIndex else { return }

        previousDayIndex = index
        selectedWeekday = weekdays[index]
        selectedDate = days[index].date
        weekStripView.select(date: days[index].date)

        let offset = CGFloat(index) * pagingScrollView.bounds.width
        pagingScrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: true)
    }

    // MARK: - Greeting

    private let greetings = ["Hey", "Hi", "Hello", "'Sup", "What's Good", "Let's Ride", "Ready", "Let's Go", "Let's Get It", "What's Up", "Yo"]

    private func showGreetingIfNeeded() {
        guard !hasShownGreeting,
              let name = profileStore.displayName, !name.isEmpty else { return }
        hasShownGreeting = true
        playGreeting(for: name)
    }

    private func playGreeting(for name: String) {
        greetingWorkItem?.cancel()

        let originalText = headerLabel.text ?? ""
        guard let picked = greetings.randomElement() else { return }
        let needsQuestion = picked == "Ready" || picked == "What's Good" || picked == "What's Up"
        let greeting = "\(picked), \(name)\(needsQuestion ? "?" : "")"

        // Fade date → greeting
        UIView.transition(with: headerLabel, duration: 0.3, options: .transitionCrossDissolve) {
            self.headerLabel.text = greeting
        } completion: { [weak self] _ in
            guard let self else { return }
            // Hold greeting, then fade back to date
            let restore = DispatchWorkItem { [weak self] in
                guard let self else { return }
                UIView.transition(with: self.headerLabel, duration: 0.3, options: .transitionCrossDissolve) {
                    self.headerLabel.text = originalText
                }
            }
            self.greetingWorkItem = restore
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: restore)
        }
    }

    @objc private func handleNameChange() {
        guard let name = profileStore.displayName, !name.isEmpty else { return }
        hasShownGreeting = true
        playGreeting(for: name)
    }

    deinit {
        greetingWorkItem?.cancel()
        streakCountTimer?.invalidate()
        streakCountTimer = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func configureDays() {
        let today = Date()
        var sundayCalendar = isoCalendar
        sundayCalendar.firstWeekday = 1
        sundayCalendar.minimumDaysInFirstWeek = 1
        let startOfWeek = sundayCalendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = sundayCalendar
        dayFormatter.dateFormat = "EEE"

        let numberFormatter = DateFormatter()
        numberFormatter.calendar = sundayCalendar
        numberFormatter.dateFormat = "d"

        var computedDays: [WeekdayStripView.Day] = []
        for offset in 0..<7 {
            guard let date = isoCalendar.date(byAdding: .day, value: offset, to: startOfWeek) else {
                continue
            }
            let symbol = dayFormatter.string(from: date)
            let shortLabel = numberFormatter.string(from: date)
            computedDays.append(.init(date: date, symbol: symbol, shortLabel: shortLabel))
        }
        days = computedDays

        // Update header with week start date
        if let firstDay = computedDays.first {
            let headerFormatter = DateFormatter()
            headerFormatter.dateFormat = "dd-MMM"
            headerLabel.text = "Week of \(headerFormatter.string(from: firstDay.date))"
        }

        let isoWeekday = isoCalendar.component(.weekday, from: today)
        selectedWeekday = weekdayFromISO(isoWeekday)
        selectedDate = today
        previousDayIndex = indexForWeekday(selectedWeekday)
    }

    private func configureLayout() {
        // Streak badge setup
        streakBadge.addSubview(streakIcon)
        streakBadge.addSubview(streakLabel)

        NSLayoutConstraint.activate([
            streakIcon.leadingAnchor.constraint(equalTo: streakBadge.leadingAnchor, constant: 8),
            streakIcon.centerYAnchor.constraint(equalTo: streakBadge.centerYAnchor),
            streakIcon.widthAnchor.constraint(equalToConstant: 16),
            streakIcon.heightAnchor.constraint(equalToConstant: 16),

            streakLabel.leadingAnchor.constraint(equalTo: streakIcon.trailingAnchor, constant: 4),
            streakLabel.trailingAnchor.constraint(equalTo: streakBadge.trailingAnchor, constant: -8),
            streakLabel.centerYAnchor.constraint(equalTo: streakBadge.centerYAnchor),

            streakBadge.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Add button action
        addButton.addTarget(self, action: #selector(addWorkoutTapped), for: .touchUpInside)

        // Tap header label to jump to today
        let headerTap = UITapGestureRecognizer(target: self, action: #selector(headerLabelTapped))
        headerLabel.addGestureRecognizer(headerTap)

        // Right side: streak badge + add button
        let rightStack = UIStackView(arrangedSubviews: [streakBadge, addButton])
        rightStack.axis = .horizontal
        rightStack.alignment = .center
        rightStack.spacing = 12

        // Header row with title on left, streak + add on right
        let headerRow = UIStackView(arrangedSubviews: [headerLabel, rightStack])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.distribution = .equalSpacing

        let headerStack = UIStackView(arrangedSubviews: [headerRow, weekStripView])
        headerStack.axis = .vertical
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // Add paging scroll view first (behind everything)
        view.addSubview(pagingScrollView)

        // Content view inside the paging scroll view
        pagingScrollView.addSubview(pagingContentView)

        // Add status bar background (above paging, below header)
        view.addSubview(statusBarBackgroundView)

        // Add header container with blur background on top
        headerContainer.addSubview(headerBackgroundView)
        headerContainer.addSubview(headerBlurView)
        headerContainer.addSubview(headerStack)
        view.addSubview(headerContainer)

        NSLayoutConstraint.activate([
            // Status bar background covers just the status bar area
            statusBarBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            statusBarBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarBackgroundView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            // Header container is a floating island at the top
            headerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            // Background fills the container
            headerBackgroundView.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            headerBackgroundView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            headerBackgroundView.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            headerBackgroundView.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),

            // Blur fills the container
            headerBlurView.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            headerBlurView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            headerBlurView.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            headerBlurView.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),

            // Header stack positioned within container
            headerStack.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            headerStack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -12),

            // Add button minimum touch target
            addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            addButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            weekStripView.heightAnchor.constraint(equalToConstant: 72),

            // Paging scroll view extends from top to bottom
            pagingScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pagingScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagingScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagingScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Content view pins to scroll view's content layout guide
            pagingContentView.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
            pagingContentView.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),
            pagingContentView.leadingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.leadingAnchor),
            pagingContentView.trailingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.trailingAnchor),

            // Content view height matches scroll view frame (no vertical scrolling in paging view)
            pagingContentView.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),

            // Content view is 7 pages wide
            pagingContentView.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor, multiplier: 7),
        ])

        updateStreakBadge(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update table view content inset to account for floating header
        // Header starts 4pt below safe area + header height + 8pt bottom spacing
        let headerHeight = headerContainer.frame.height + 4 + 8
        let tabBarHeight = tabBarController?.tabBar.frame.height ?? 0
        let tabBarMaxY = tabBarController?.tabBar.frame.maxY ?? view.bounds.height
        let bottomGap = max(0, view.bounds.height - tabBarMaxY)
        let bottomPadding = tabBarHeight + (bottomGap * 2)
        for tv in dayTableViews {
            tv.contentInset.top = headerHeight
            tv.contentInset.bottom = bottomPadding
            tv.verticalScrollIndicatorInsets.top = headerHeight
            tv.verticalScrollIndicatorInsets.bottom = bottomPadding
        }

        // Scroll to the initial day once layout is ready
        if !hasScrolledToInitialDay {
            hasScrolledToInitialDay = true
            let offset = CGFloat(previousDayIndex) * pagingScrollView.bounds.width
            pagingScrollView.contentOffset = CGPoint(x: offset, y: 0)
        }
    }

    private func configureWeekStrip() {
        weekStripView.configure(days: days, selectedIndex: indexForWeekday(selectedWeekday))
        updateWeekStripIndicators()
        weekStripView.onSelectionChanged = { [weak self] selection in
            guard let self else { return }
            let index = selection.index
            guard index >= 0, index < self.weekdays.count, index < self.days.count else { return }
            guard index != self.previousDayIndex else { return }

            self.previousDayIndex = index
            self.selectedWeekday = self.weekdays[index]
            self.selectedDate = self.days[index].date

            let offset = CGFloat(index) * self.pagingScrollView.bounds.width
            self.pagingScrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: true)
        }
    }

    // MARK: - Table Views (one per day)

    private func configureTableViews() {
        pagingScrollView.delegate = self

        for i in 0..<7 {
            let tv = UITableView(frame: .zero, style: .insetGrouped)
            tv.translatesAutoresizingMaskIntoConstraints = false
            tv.backgroundColor = .clear
            tv.separatorEffect = UIVibrancyEffect(
                blurEffect: UIBlurEffect(style: .systemUltraThinMaterial))
            tv.sectionHeaderTopPadding = 12
            tv.delegate = self
            tv.register(ScheduleWorkoutCell.self, forCellReuseIdentifier: ScheduleWorkoutCell.reuseIdentifier)

            pagingContentView.addSubview(tv)

            NSLayoutConstraint.activate([
                tv.topAnchor.constraint(equalTo: pagingContentView.topAnchor),
                tv.bottomAnchor.constraint(equalTo: pagingContentView.bottomAnchor),
                tv.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor),
            ])

            if i == 0 {
                tv.leadingAnchor.constraint(equalTo: pagingContentView.leadingAnchor).isActive = true
            } else {
                tv.leadingAnchor.constraint(equalTo: dayTableViews[i - 1].trailingAnchor).isActive = true
            }

            dayTableViews.append(tv)
        }

        pagingScrollView.dayTableViews = dayTableViews
    }

    private func configureDataSources() {
        for i in 0..<7 {
            let dayIndex = i
            let ds = UITableViewDiffableDataSource<Section, WorkoutTemplate>(
                tableView: dayTableViews[i]
            ) { [weak self] (tableView: UITableView, indexPath: IndexPath, workout: WorkoutTemplate) in
                guard let self else { return UITableViewCell() }
                guard dayIndex >= 0, dayIndex < self.days.count else { return UITableViewCell() }
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: ScheduleWorkoutCell.reuseIdentifier,
                    for: indexPath
                ) as? ScheduleWorkoutCell else {
                    return UITableViewCell()
                }

                let date = self.days[dayIndex].date
                let resolved = self.snapshotStore.snapshot(for: workout.id, on: date) ?? workout
                var completions: [UUID: Bool] = [:]
                var logs: [UUID: ExerciseLog] = [:]
                for exercise in resolved.exercises {
                    completions[exercise.id] = self.completionStore.isExerciseCompleted(
                        exerciseId: exercise.id,
                        in: workout.id,
                        on: date
                    )
                    if let log = self.weightLogStore.log(for: exercise.id, in: workout.id, on: date) {
                        logs[exercise.id] = log
                    }
                }

                cell.configure(with: resolved, completions: completions, logs: logs, expandedExercises: self.expandedExercises)
                cell.delegate = self

                cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
                cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
                return cell
            }
            dayDataSources.append(ds)
        }
    }

    // MARK: - Snapshots

    private func applyAllSnapshots(animated: Bool) {
        for i in 0..<7 {
            applySnapshot(for: i, animated: animated)
        }
        updateWeekStripIndicators()
    }

    private func applySnapshot(for dayIndex: Int, animated: Bool) {
        guard dayIndex >= 0, dayIndex < 7 else { return }
        let weekday = weekdays[dayIndex]
        var snapshot = NSDiffableDataSourceSnapshot<Section, WorkoutTemplate>()
        snapshot.appendSections([.main])
        let workouts = store.workouts(for: weekday)
        snapshot.appendItems(workouts, toSection: .main)
        snapshot.reloadSections([.main])
        dayDataSources[dayIndex].apply(snapshot, animatingDifferences: animated)

        // Per-table empty state
        if workouts.isEmpty {
            let label = UILabel()
            label.text = "No workouts yet.\nTap + to add workouts."
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            label.font = .preferredFont(forTextStyle: .body)
            label.numberOfLines = 0
            dayTableViews[dayIndex].backgroundView = label
        } else {
            dayTableViews[dayIndex].backgroundView = nil
        }
    }

    private func scrollToPendingExpansionIfNeeded() {
        guard let workoutId = pendingScrollToWorkoutId,
              let exerciseId = pendingScrollToExerciseId else { return }
        pendingScrollToWorkoutId = nil
        pendingScrollToExerciseId = nil

        let dayIndex = indexForWeekday(selectedWeekday)
        guard dayIndex >= 0, dayIndex < dayDataSources.count else { return }
        let dataSource = dayDataSources[dayIndex]
        let tableView = dayTableViews[dayIndex]
        let snapshot = dataSource.snapshot()

        guard let workout = snapshot.itemIdentifiers.first(where: { $0.id == workoutId }),
              let indexPath = dataSource.indexPath(for: workout) else { return }

        tableView.layoutIfNeeded()
        if tableView.cellForRow(at: indexPath) == nil {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
            tableView.layoutIfNeeded()
        }

        guard let cell = tableView.cellForRow(at: indexPath) as? ScheduleWorkoutCell else { return }
        let exerciseRectInCell = cell.rectForExercise(exerciseId: exerciseId) ?? cell.bounds
        let exerciseRect = tableView.convert(exerciseRectInCell, from: cell)
        let visibleHeight = tableView.bounds.height
            - tableView.adjustedContentInset.top
            - tableView.adjustedContentInset.bottom
        guard visibleHeight > 0 else { return }

        let topPadding: CGFloat = 12
        let bottomPadding: CGFloat = 12
        let visibleTop = tableView.contentOffset.y + tableView.adjustedContentInset.top
        let visibleBottom = tableView.contentOffset.y
            + tableView.bounds.height
            - tableView.adjustedContentInset.bottom

        let minOffsetY = -tableView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            tableView.contentSize.height - visibleHeight + tableView.adjustedContentInset.bottom
        )
        let topOffsetY = exerciseRect.minY - topPadding - tableView.adjustedContentInset.top
        let bottomOffsetY = exerciseRect.maxY + bottomPadding - tableView.bounds.height + tableView.adjustedContentInset.bottom
        let cellTooTall = exerciseRect.height + topPadding + bottomPadding > visibleHeight
        var targetOffsetY: CGFloat?

        if cellTooTall {
            if exerciseRect.minY - topPadding < visibleTop || exerciseRect.maxY + bottomPadding > visibleBottom {
                targetOffsetY = topOffsetY
            }
        } else if exerciseRect.minY - topPadding < visibleTop {
            targetOffsetY = topOffsetY
        } else if exerciseRect.maxY + bottomPadding > visibleBottom {
            targetOffsetY = bottomOffsetY
        }

        guard let unclampedOffset = targetOffsetY else { return }
        let clampedOffset = min(max(unclampedOffset, minOffsetY), maxOffsetY)
        tableView.setContentOffset(CGPoint(x: 0, y: clampedOffset), animated: true)
    }

    private func updateWeekStripIndicators() {
        let datesWithWorkouts = weekdays.enumerated().compactMap { index, weekday -> Date? in
            guard index < days.count else { return nil }
            return store.workouts(for: weekday).isEmpty ? nil : days[index].date
        }

        let completedDatesInWeek = weekdays.enumerated().compactMap { index, weekday -> Date? in
            guard index < days.count else { return nil }
            let dayDate = days[index].date
            let workouts = store.workouts(for: weekday)
            guard !workouts.isEmpty else { return nil }

            let allWorkoutsCompleted = workouts.allSatisfy { workout in
                let resolved = snapshotStore.snapshot(for: workout.id, on: dayDate) ?? workout
                return completionStore.isWorkoutFullyCompleted(resolved, on: dayDate)
            }
            return allWorkoutsCompleted ? dayDate : nil
        }

        // Get PR dates for the current week
        let prDatesInWeek = days.compactMap { day -> Date? in
            weightLogStore.hasPR(on: day.date) ? day.date : nil
        }

        weekStripView.setIndicators(
            datesWithWorkouts,
            prDates: prDatesInWeek,
            completedDates: completedDatesInWeek
        )
    }

    private func updateStreakBadge(animated: Bool) {
        let streak = streakStore.currentStreak
        streakCountTimer?.invalidate()
        streakCountTimer = nil

        if streak == 0 {
            streakLabel.text = "0"
            streakBadge.isHidden = true
            streakBadge.alpha = 1
            streakBadge.transform = .identity
            lastStreakValue = streak
            return
        }

        streakBadge.isHidden = false
        if animated, lastStreakValue == 0 {
            animateStreakStart(to: streak)
        } else if animated, streak > lastStreakValue {
            animateStreakIncrement(to: streak)
        } else {
            streakLabel.text = "\(streak)"
            streakBadge.alpha = 1
            streakBadge.transform = .identity
        }
        lastStreakValue = streak
    }

    private func animateStreakIncrement(to streak: Int) {
        streakLabel.text = "\(streak)"
        streakBadge.transform = .identity

        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 1.18, 0.98, 1.06, 1.0]
        bounce.keyTimes = [0, 0.35, 0.6, 0.85, 1]
        bounce.duration = 0.35
        bounce.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeOut),
        ]
        streakBadge.layer.add(bounce, forKey: "streakBounce")
    }

    private func animateStreakStart(to streak: Int) {
        streakLabel.text = "0"
        startStreakCountUp(to: streak)

        streakBadge.alpha = 0
        streakBadge.transform = CGAffineTransform(scaleX: 0.35, y: 0.35)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            self.streakBadge.alpha = 1
            self.streakBadge.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                self.streakBadge.transform = .identity
            }
        }

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.4, 1.2, 0.95, 1.05, 1.0]
        pop.keyTimes = [0, 0.45, 0.7, 0.9, 1]
        pop.duration = 0.45
        pop.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeOut),
        ]
        streakBadge.layer.add(pop, forKey: "streakPopIn")
    }

    private func startStreakCountUp(to streak: Int) {
        let steps = max(1, min(streak, 20))
        let increment = max(1, Int(ceil(Double(streak) / Double(steps))))
        let interval = max(0.03, 0.6 / Double(steps))
        var current = 0

        streakCountTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] timer in
            guard let self else { return }
            current = min(streak, current + increment)
            self.streakLabel.text = "\(current)"
            if current >= streak {
                timer.invalidate()
                self.streakCountTimer = nil
            }
        }
    }

    // MARK: - Observers

    private func observeScheduleChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScheduleChange),
            name: ScheduleStore.scheduleDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCompletionChange),
            name: CompletionStore.completionsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStreakChange),
            name: StreakStore.streakDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNameChange),
            name: UserProfileStore.nameDidChangeNotification,
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
            selector: #selector(handleLibraryChange),
            name: WorkoutLibraryStore.libraryDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMachineChange),
            name: MachineStore.machinesDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleScheduleChange() {
        applyAllSnapshots(animated: true)
    }

    @objc private func handleCompletionChange() {
        applyAllSnapshots(animated: false)
        DispatchQueue.main.async { [weak self] in
            self?.scrollToPendingExpansionIfNeeded()
        }
    }

    @objc private func handleStreakChange() {
        updateStreakBadge(animated: true)
    }

    @objc private func handleWeightLogChange() {
        applyAllSnapshots(animated: false)
    }

    @objc private func handleLibraryChange() {
        // Update existing snapshots with latest template data so edits propagate
        for template in libraryStore.templates {
            snapshotStore.updateSnapshots(for: template)
        }
        applyAllSnapshots(animated: false)
    }

    @objc private func handleMachineChange() {
        // Machine edits affect exercise display (weight increments, names)
        applyAllSnapshots(animated: false)
    }

    @objc private func headerLabelTapped() {
        let isoWeekday = isoCalendar.component(.weekday, from: Date())
        let todayWeekday = weekdayFromISO(isoWeekday)
        let todayIndex = indexForWeekday(todayWeekday)
        HapticManager.shared.light()
        selectDay(at: todayIndex)
    }

    @objc private func addWorkoutTapped() {
        HapticManager.shared.light()
        let selectedWorkouts = store.workouts(for: selectedWeekday)
        let picker = WorkoutPickerViewController(
            allWorkouts: store.availableWorkouts,
            preselected: selectedWorkouts
        )
        picker.delegate = self
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    // MARK: - Helpers

    private func dayIndex(for tableView: UITableView) -> Int? {
        dayTableViews.firstIndex(of: tableView)
    }

    private func weekdayFromISO(_ isoWeekday: Int) -> Weekday {
        switch isoWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .saturday
        }
    }

    private func indexForWeekday(_ weekday: Weekday) -> Int {
        Weekday.allCases.firstIndex(of: weekday) ?? 0
    }
}

// MARK: - UITableViewDelegate

extension ScheduleViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let dayIdx = dayIndex(for: tableView) else { return nil }
        let weekday = weekdays[dayIdx]
        let label = UILabel()
        let workouts = store.workouts(for: weekday)
        var uniqueNames: [String] = []
        for name in workouts.map(\.name) where !name.isEmpty {
            if !uniqueNames.contains(name) {
                uniqueNames.append(name)
            }
        }

        if uniqueNames.isEmpty {
            label.text = weekday.fullSymbol
        } else {
            let groupText = uniqueNames.joined(separator: ", ")
            label.text = "\(weekday.fullSymbol) — \(groupText)"
        }

        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let dayIdx = dayIndex(for: tableView) else { return nil }
        let weekday = weekdays[dayIdx]
        guard let workout = dayDataSources[dayIdx].itemIdentifier(for: indexPath) else { return nil }
        let date = days[dayIdx].date
        let delete = UIContextualAction(style: .destructive, title: "Remove") {
            [weak self] _, _, completion in
            // Clear day-specific completion/log/snapshot data
            CompletionStore.shared.clearCompletions(for: workout.id, on: date)
            WeightLogStore.shared.deleteLogs(for: workout.id, on: date)
            WorkoutSnapshotStore.shared.deleteSnapshot(for: workout.id, on: date)
            self?.store.remove(templateId: workout.id, from: weekday)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === pagingScrollView {
            // Don't update selection until the initial scroll to today has happened
            guard hasScrolledToInitialDay else { return }
            // Horizontal paging — update selected day as user drags
            let pageWidth = pagingScrollView.bounds.width
            guard pageWidth > 0 else { return }
            let currentPage = Int(round(pagingScrollView.contentOffset.x / pageWidth))
            let clampedPage = max(0, min(days.count - 1, currentPage))

            if clampedPage != previousDayIndex {
                previousDayIndex = clampedPage
                selectedWeekday = weekdays[clampedPage]
                selectedDate = days[clampedPage].date
                weekStripView.select(date: days[clampedPage].date)
            }
        } else {
            // Vertical scroll in a day's table view — update header shadow
            let contentInsetTop = scrollView.contentInset.top
            let offsetY = scrollView.contentOffset.y + contentInsetTop

            let scrollProgress = min(max(offsetY / 50.0, 0), 1)
            let backgroundAlpha = 0.6 + (scrollProgress * 0.3)
            headerBackgroundView.backgroundColor = UIColor.systemBackground.withAlphaComponent(backgroundAlpha)

            let baseShadow: Float = 0.08
            let additionalShadow: Float = 0.12
            headerContainer.layer.shadowOpacity = baseShadow + Float(scrollProgress) * additionalShadow
        }
    }

}

// MARK: - WorkoutPickerViewControllerDelegate

extension ScheduleViewController: WorkoutPickerViewControllerDelegate {
    func workoutPicker(
        _ controller: WorkoutPickerViewController, didSelectWorkouts workouts: [WorkoutTemplate]
    ) {
        store.replace(day: selectedWeekday, with: workouts)
    }
}

// MARK: - ScheduleWorkoutCellDelegate

extension ScheduleViewController: ScheduleWorkoutCellDelegate {
    func scheduleWorkoutCell(
        _ cell: ScheduleWorkoutCell,
        didToggleExercise exercise: WorkoutTemplate.Exercise,
        in workout: WorkoutTemplate
    ) {
        snapshotStore.captureIfNeeded(workout, on: selectedDate)
        let resolved = snapshotStore.snapshot(for: workout.id, on: selectedDate) ?? workout
        let wasFullyCompleted = completionStore.isWorkoutFullyCompleted(resolved, on: selectedDate)

        let wasCompleted = completionStore.isExerciseCompleted(
            exerciseId: exercise.id,
            in: workout.id,
            on: selectedDate
        )
        let isNowCompleted = !wasCompleted
        let hasExistingLog = weightLogStore.log(for: exercise.id, in: workout.id, on: selectedDate) != nil
        if isNowCompleted && !hasExistingLog {
            expandedExercises = [exercise.id]
            pendingScrollToWorkoutId = workout.id
            pendingScrollToExerciseId = exercise.id
        } else if !isNowCompleted {
            expandedExercises.remove(exercise.id)
            pendingScrollToWorkoutId = nil
            pendingScrollToExerciseId = nil
        } else {
            pendingScrollToWorkoutId = nil
            pendingScrollToExerciseId = nil
        }

        completionStore.toggleExerciseCompletion(
            exerciseId: exercise.id,
            in: workout.id,
            on: selectedDate
        )

        completionStore.checkAndRecordWorkoutCompletion(
            for: resolved,
            on: selectedDate,
            wasFullyCompleted: wasFullyCompleted
        )
    }

    func scheduleWorkoutCell(
        _ cell: ScheduleWorkoutCell,
        didConfirmSetWeights setWeights: [Double],
        wasModified: Bool,
        for exercise: WorkoutTemplate.Exercise,
        in workout: WorkoutTemplate
    ) -> Bool {
        let weight = setWeights.max() ?? 0

        // Only check for PR if user actually modified the weight
        let isPR = wasModified && weightLogStore.isPersonalRecord(exerciseId: exercise.exerciseId, weight: weight)

        let log = ExerciseLog(
            entryId: exercise.id,
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.name,
            workoutId: workout.id,
            date: selectedDate,
            weight: weight,
            reps: 0,
            unit: weightLogStore.preferredUnit,
            isPersonalRecord: isPR,
            setWeights: setWeights
        )
        weightLogStore.saveLog(log)

        if isPR {
            HapticManager.shared.celebration()
        }

        return isPR
    }

    func scheduleWorkoutCellDidToggleExpand(_ cell: ScheduleWorkoutCell, exerciseId: UUID) {
        if expandedExercises.contains(exerciseId) {
            expandedExercises.remove(exerciseId)
        } else {
            expandedExercises.insert(exerciseId)
        }
    }

    func scheduleWorkoutCellNeedsResize(_ cell: ScheduleWorkoutCell) {
        // Find which table view contains this cell and trigger height recalculation
        for tv in dayTableViews {
            if tv.visibleCells.contains(cell) {
                tv.performBatchUpdates(nil)
                break
            }
        }
    }

    func scheduleWorkoutCellDidTapStartWorkout(_ cell: ScheduleWorkoutCell, workout: WorkoutTemplate) {
        let timerVC = WorkoutTimerViewController(workout: workout, selectedDate: selectedDate)
        timerVC.delegate = self
        present(timerVC, animated: true)
    }

    func scheduleWorkoutCell(_ cell: ScheduleWorkoutCell, didTapTimerForExercise exercise: WorkoutTemplate.Exercise, in workout: WorkoutTemplate) {
        let timerVC = WorkoutTimerViewController(exercise: exercise, workout: workout, selectedDate: selectedDate)
        timerVC.delegate = self
        present(timerVC, animated: true)
    }

    func scheduleWorkoutCellDidLongPress(_ cell: ScheduleWorkoutCell) {
        let dayIndex = indexForWeekday(selectedWeekday)
        let tableView = dayTableViews[dayIndex]

        let visibleWidth = tableView.bounds.width
        let visibleHeight = tableView.bounds.height

        guard tableView.contentSize.height > 0, visibleHeight > 0 else { return }

        let savedOffset = tableView.contentOffset

        // Scroll through all content to force self-sizing cells to calculate actual heights,
        // so contentSize reflects the true total height instead of estimated heights.
        var yOffset: CGFloat = 0
        while yOffset < tableView.contentSize.height {
            tableView.contentOffset = CGPoint(x: 0, y: yOffset)
            tableView.layoutIfNeeded()
            yOffset += visibleHeight
        }

        let contentHeight = tableView.contentSize.height
        let captureSize = CGSize(width: visibleWidth, height: contentHeight)

        let format = UIGraphicsImageRendererFormat()
        format.scale = tableView.window?.windowScene?.screen.scale ?? 3.0
        let renderer = UIGraphicsImageRenderer(size: captureSize, format: format)

        let image = renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: captureSize))

            let pages = Int(ceil(contentHeight / visibleHeight))
            for page in 0..<pages {
                let yOff = CGFloat(page) * visibleHeight
                tableView.contentOffset = CGPoint(x: 0, y: yOff)
                tableView.layoutIfNeeded()

                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: yOff)
                tableView.drawHierarchy(
                    in: CGRect(origin: .zero, size: CGSize(width: visibleWidth, height: visibleHeight)),
                    afterScreenUpdates: true
                )
                ctx.cgContext.restoreGState()
            }
        }

        tableView.contentOffset = savedOffset

        UIPasteboard.general.image = image
        HapticManager.shared.success()
        showCopiedToast()
    }

    private func showCopiedToast() {
        let toast = UILabel()
        toast.text = "Copied to Clipboard"
        toast.font = .systemFont(ofSize: 14, weight: .semibold)
        toast.textColor = .white
        toast.textAlignment = .center
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toast.layer.cornerRadius = 16
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false

        let padding: CGFloat = 24
        toast.frame.size = CGSize(
            width: toast.intrinsicContentSize.width + padding * 2,
            height: toast.intrinsicContentSize.height + padding * 0.75
        )

        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            toast.widthAnchor.constraint(equalToConstant: toast.frame.width),
            toast.heightAnchor.constraint(equalToConstant: toast.frame.height),
        ])

        toast.alpha = 0
        toast.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.2) {
            toast.alpha = 1
            toast.transform = .identity
        }

        UIView.animate(withDuration: 0.3, delay: 1.2, options: []) {
            toast.alpha = 0
            toast.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            toast.removeFromSuperview()
        }
    }

}

// MARK: - WorkoutTimerViewControllerDelegate

extension ScheduleViewController: WorkoutTimerViewControllerDelegate {
    func workoutTimer(_ controller: WorkoutTimerViewController, didCompleteExercise exercise: WorkoutTemplate.Exercise, in workout: WorkoutTemplate) {
        snapshotStore.captureIfNeeded(workout, on: selectedDate)
        let resolved = snapshotStore.snapshot(for: workout.id, on: selectedDate) ?? workout
        let wasFullyCompleted = completionStore.isWorkoutFullyCompleted(resolved, on: selectedDate)

        completionStore.setExerciseCompleted(true, exerciseId: exercise.id, in: workout.id, on: selectedDate)

        completionStore.checkAndRecordWorkoutCompletion(
            for: resolved,
            on: selectedDate,
            wasFullyCompleted: wasFullyCompleted
        )
    }

    func workoutTimerDidComplete(_ controller: WorkoutTimerViewController, workout: WorkoutTemplate) {
        // Individual exercises are already marked complete via workoutTimer(_:didCompleteExercise:in:)
    }

    func workoutTimerDidCancel(_ controller: WorkoutTimerViewController) {
        // Completed exercises are already saved — remaining exercises stay incomplete
    }
}

// MARK: - PagingScrollView

/// Horizontal paging scroll view that only begins its pan gesture for clearly
/// horizontal drags and ignores touches on table view cells (so swipe-to-delete works).
private final class PagingScrollView: UIScrollView {
    var dayTableViews: [UITableView] = []

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              pan === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        // Reject vertical and diagonal gestures
        let velocity = pan.velocity(in: self)
        guard abs(velocity.x) > abs(velocity.y) else { return false }

        // Don't page when swiping on a cell — let swipe-to-delete handle it
        let location = pan.location(in: self)
        for tv in dayTableViews {
            let point = convert(location, to: tv)
            if tv.bounds.contains(point), tv.indexPathForRow(at: point) != nil {
                return false
            }
        }

        return true
    }
}

// MARK: - Detail

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
