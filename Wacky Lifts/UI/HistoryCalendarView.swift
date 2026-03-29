import UIKit

protocol HistoryCalendarViewDelegate: AnyObject {
    func historyCalendarView(_ view: HistoryCalendarView, didSelectDate date: Date)
}

final class HistoryCalendarView: UIView {

    weak var delegate: HistoryCalendarViewDelegate?

    private let calendar = Calendar.current
    private var currentMonth: Date = Date()
    private let streakStore = StreakStore.shared
    private let weightLogStore = WeightLogStore.shared

    private let headerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let monthLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private let prevButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        button.setImage(UIImage(systemName: "chevron.left", withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = "Previous month"
        return button
    }()

    private let nextButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        button.setImage(UIImage(systemName: "chevron.right", withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = "Next month"
        return button
    }()

    private let weekdayStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let daysGrid: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 16
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        updateCalendar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(containerView)

        // Header with month navigation
        prevButton.addTarget(self, action: #selector(prevMonthTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonthTapped), for: .touchUpInside)

        headerStack.addArrangedSubview(prevButton)
        headerStack.addArrangedSubview(monthLabel)
        headerStack.addArrangedSubview(nextButton)

        containerView.addSubview(headerStack)
        containerView.addSubview(weekdayStack)
        containerView.addSubview(daysGrid)

        // Weekday headers
        let weekdaySymbols = calendar.veryShortWeekdaySymbols
        for symbol in weekdaySymbols {
            let label = UILabel()
            label.text = symbol
            label.font = .preferredFont(forTextStyle: .caption2)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            weekdayStack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            weekdayStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            weekdayStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            weekdayStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

            daysGrid.topAnchor.constraint(equalTo: weekdayStack.bottomAnchor, constant: 8),
            daysGrid.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            daysGrid.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            daysGrid.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
        ])
    }

    private func updateCalendar() {
        // Update month label
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        monthLabel.text = formatter.string(from: currentMonth)

        // Disable next button if current month is this month or future
        let today = Date()
        let isCurrentOrFutureMonth = calendar.compare(currentMonth, to: today, toGranularity: .month) != .orderedAscending
        nextButton.isEnabled = !isCurrentOrFutureMonth
        nextButton.alpha = isCurrentOrFutureMonth ? 0.3 : 1.0

        // Clear existing day views
        daysGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Get activity data for the month
        let activityDates = Set(streakStore.activityDates(in: currentMonth).map {
            calendar.startOfDay(for: $0)
        })
        let workoutDates = Set(streakStore.workoutDates(in: currentMonth).map {
            calendar.startOfDay(for: $0)
        })
        let prDates = Set(weightLogStore.prDates(in: currentMonth).map {
            calendar.startOfDay(for: $0)
        })

        // Calculate days to display
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return }

        let firstDayOfGrid = firstWeek.start
        var currentDate = firstDayOfGrid
        var weekStack: UIStackView?

        // Generate 6 weeks of days (max needed for any month)
        for _ in 0..<42 {
            if calendar.component(.weekday, from: currentDate) == calendar.firstWeekday || weekStack == nil {
                weekStack = UIStackView()
                weekStack?.axis = .horizontal
                weekStack?.distribution = .fillEqually
                weekStack?.spacing = 4
                daysGrid.addArrangedSubview(weekStack!)
            }

            let dayView = makeDayView(
                for: currentDate,
                isCurrentMonth: calendar.isDate(currentDate, equalTo: currentMonth, toGranularity: .month),
                hasActivity: activityDates.contains(calendar.startOfDay(for: currentDate)),
                hasWorkout: workoutDates.contains(calendar.startOfDay(for: currentDate)),
                hasPR: prDates.contains(calendar.startOfDay(for: currentDate))
            )
            weekStack?.addArrangedSubview(dayView)

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate

            // Stop after 6 weeks
            if let lastWeek = daysGrid.arrangedSubviews.last as? UIStackView,
               lastWeek.arrangedSubviews.count == 7,
               daysGrid.arrangedSubviews.count >= 6 {
                break
            }
        }
    }

    private func makeDayView(for date: Date, isCurrentMonth: Bool, hasActivity: Bool, hasWorkout: Bool, hasPR: Bool) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let dayNumber = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)

        let label = UILabel()
        label.text = "\(dayNumber)"
        label.font = .preferredFont(forTextStyle: .body)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        if !isCurrentMonth {
            label.textColor = .quaternaryLabel
        } else if isToday {
            label.textColor = .systemBlue
            label.font = .systemFont(ofSize: label.font.pointSize, weight: .bold)
        } else {
            label.textColor = .label
        }

        container.addSubview(label)

        // Add activity indicator dot
        // Priority: Gold for PR, Green for workout, Gray for activity only
        let showDot = (hasActivity || hasPR) && isCurrentMonth
        if showDot {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false

            if hasPR {
                dot.backgroundColor = .systemYellow
            } else if hasWorkout {
                dot.backgroundColor = .systemGreen
            } else {
                dot.backgroundColor = .systemGray
            }

            dot.layer.cornerRadius = 3
            container.addSubview(dot)

            NSLayoutConstraint.activate([
                dot.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                dot.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2),
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6),
            ])
        }

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            container.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Add tap gesture if there's activity or PR (PR dates tappable forever)
        if (hasActivity || hasPR) && isCurrentMonth {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dayTapped(_:)))
            container.addGestureRecognizer(tapGesture)
            container.isUserInteractionEnabled = true
            container.tag = Int(date.timeIntervalSince1970)
        }

        return container
    }

    @objc private func prevMonthTapped() {
        guard let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) else { return }
        currentMonth = newMonth
        updateCalendar()
    }

    @objc private func nextMonthTapped() {
        guard let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else { return }
        currentMonth = newMonth
        updateCalendar()
    }

    @objc private func dayTapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        let date = Date(timeIntervalSince1970: TimeInterval(view.tag))
        delegate?.historyCalendarView(self, didSelectDate: date)
    }

    func refresh() {
        updateCalendar()
    }
}
