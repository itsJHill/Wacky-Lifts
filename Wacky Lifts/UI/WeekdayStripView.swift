import UIKit

public final class WeekdayStripView: UIView {

    public struct Day: Hashable {
        public let date: Date
        public let symbol: String
        public let shortLabel: String

        public init(date: Date, symbol: String, shortLabel: String) {
            self.date = date
            self.symbol = symbol
            self.shortLabel = shortLabel
        }
    }

    public struct Selection {
        public let day: Day
        public let index: Int
    }

    public var onSelectionChanged: ((Selection) -> Void)?

    private let calendar = Calendar.current
    private var days: [Day] = []
    private var selectedIndex: Int = 0

    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = 16
        return view
    }()

    private let selectionShadow: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.12
        view.layer.shadowRadius = 6
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        return view
    }()

    private let selectionIndicator: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemThickMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        view.contentView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
        return view
    }()

    private let stackView: UIStackView = {
        let view = UIStackView()
        view.axis = .horizontal
        view.spacing = 8
        view.alignment = .center
        view.distribution = .fillEqually
        return view
    }()

    private var buttons: [UIButton] = []
    private var dotViews: [UIView] = []
    private var indicatorDates: [Date] = []
    private var prDates: [Date] = []
    private var completedDates: [Date] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        configureForCurrentWeek()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        configureForCurrentWeek()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        applyButtonStyling()
        updateSelectionIndicatorFrame(animated: false)
    }

    public func configure(days: [Day], selectedIndex: Int = 0) {
        self.days = days
        self.selectedIndex = min(max(0, selectedIndex), max(0, days.count - 1))
        reloadButtons()
        notifySelection()
    }

    public func select(date: Date) {
        guard let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) })
        else { return }
        setSelectedIndex(index, animated: true)
    }

    public func setIndicators(_ dates: [Date], prDates: [Date] = [], completedDates: [Date] = []) {
        indicatorDates = dates
        self.prDates = prDates
        self.completedDates = completedDates
        UIView.animate(withDuration: 0.2) {
            self.updateDotVisibility()
            self.layoutIfNeeded()
        }
    }

    private func setupView() {
        backgroundColor = .clear
        addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false

        blurView.contentView.addSubview(selectionShadow)
        blurView.contentView.addSubview(selectionIndicator)
        blurView.contentView.addSubview(stackView)
        blurView.contentView.bringSubviewToFront(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(
                equalTo: blurView.contentView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(
                equalTo: blurView.contentView.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(
                equalTo: blurView.contentView.bottomAnchor, constant: -8),
            stackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
    }

    private func configureForCurrentWeek() {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let daySymbols = calendar.shortWeekdaySymbols
        var weekDays: [Day] = []

        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfWeek) else {
                continue
            }
            let symbol = daySymbols[
                (calendar.component(.weekday, from: date) - 1) % daySymbols.count]
            let shortLabel = calendar.component(.day, from: date).description
            weekDays.append(Day(date: date, symbol: symbol, shortLabel: shortLabel))
        }

        configure(days: weekDays, selectedIndex: 0)
    }

    private func reloadButtons() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        dotViews.removeAll()

        days.enumerated().forEach { index, day in
            let button = makeButton(for: day, index: index)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }

        applyButtonStyling()
        updateSelectionStyles(animated: false)
        updateDotVisibility()
        updateSelectionIndicatorFrame(animated: false)
    }

    private func makeButton(for day: Day, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = index

        // Use Dynamic Type with UIFontMetrics for accessibility scaling
        let baseFont = UIFont.preferredFont(forTextStyle: .caption2)
        let scaledFont = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont.withSize(baseFont.pointSize), maximumPointSize: 18)

        // Create properly centered multiline attributed string
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 2

        let attributedTitle = NSMutableAttributedString(
            string: "\(day.symbol)\n\(day.shortLabel)",
            attributes: [
                .font: scaledFont,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: UIColor.label
            ]
        )

        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(attributedTitle)
        config.titleAlignment = .center
        config.baseForegroundColor = .label
        // Default insets - bottom will be adjusted dynamically based on dot visibility
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)

        button.configuration = config
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = 12
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)

        // Accessibility
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d"
        button.accessibilityLabel = dateFormatter.string(from: day.date)
        button.accessibilityHint = "Double tap to view workouts"

        let dotView = UIView()
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.backgroundColor = .systemBlue
        dotView.layer.cornerRadius = 3
        dotView.isHidden = true
        button.addSubview(dotView)

        if let titleLabel = button.titleLabel {
            NSLayoutConstraint.activate([
                dotView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                dotView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
                dotView.widthAnchor.constraint(equalToConstant: 6),
                dotView.heightAnchor.constraint(equalToConstant: 6),
            ])
        }

        dotViews.append(dotView)
        return button
    }

    private func applyButtonStyling() {
        buttons.forEach { button in
            button.layer.borderWidth = 0
            button.layer.borderColor = UIColor.clear.cgColor
        }
    }

    @objc private func handleTap(_ sender: UIButton) {
        setSelectedIndex(sender.tag, animated: true)
    }

    private func setSelectedIndex(_ index: Int, animated: Bool) {
        guard index != selectedIndex, index >= 0, index < days.count else { return }
        selectedIndex = index
        updateSelectionStyles(animated: animated)
        notifySelection()
    }

    private func updateSelectionStyles(animated: Bool) {
        self.updateSelectionIndicatorFrame(animated: animated)
    }

    private func updateSelectionIndicatorFrame(animated: Bool) {
        updateSelectionIndicatorFrame(for: selectedIndex, animated: animated)
    }

    private func updateSelectionIndicatorFrame(for index: Int, animated: Bool) {
        guard index >= 0, index < buttons.count else {
            selectionIndicator.isHidden = true
            selectionShadow.isHidden = true
            return
        }
        let button = buttons[index]
        stackView.layoutIfNeeded()
        blurView.contentView.layoutIfNeeded()
        let targetFrame = blurView.contentView.convert(button.frame, from: stackView)
            .insetBy(dx: 2, dy: 2)
        let cornerRadius = min(18, targetFrame.height / 2)

        selectionIndicator.isHidden = false
        selectionIndicator.alpha = 1
        selectionIndicator.layer.cornerRadius = cornerRadius

        selectionShadow.isHidden = false
        selectionShadow.layer.cornerRadius = cornerRadius

        if animated {
            if #available(iOS 17.0, *) {
                UIView.animate(springDuration: 0.44, bounce: 0.16) {
                    self.selectionIndicator.frame = targetFrame
                    self.selectionShadow.frame = targetFrame
                }
            } else {
                UIView.animate(
                    withDuration: 0.38,
                    delay: 0,
                    usingSpringWithDamping: 0.78,
                    initialSpringVelocity: 0.3,
                    options: [.curveEaseOut]
                ) {
                    self.selectionIndicator.frame = targetFrame
                    self.selectionShadow.frame = targetFrame
                }
            }
        } else {
            selectionIndicator.frame = targetFrame
            selectionShadow.frame = targetFrame
        }
    }

    private func updateDotVisibility() {
        guard !days.isEmpty else { return }
        dotViews.enumerated().forEach { index, dotView in
            guard index < days.count, index < buttons.count else { return }
            let dayDate = days[index].date
            let hasWorkout = indicatorDates.contains { calendar.isDate($0, inSameDayAs: dayDate) }
            let hasPR = prDates.contains { calendar.isDate($0, inSameDayAs: dayDate) }
            let allWorkoutsCompleted = completedDates.contains {
                calendar.isDate($0, inSameDayAs: dayDate)
            }
            dotView.isHidden = !hasWorkout

            // Gold dot for PR days, green when all workouts are completed, blue otherwise
            if hasPR {
                dotView.backgroundColor = .systemYellow
            } else if allWorkoutsCompleted {
                dotView.backgroundColor = .systemGreen
            } else {
                dotView.backgroundColor = .systemBlue
            }

            // Dynamically adjust bottom inset to include dot in selection box
            let button = buttons[index]
            var config = button.configuration
            config?.contentInsets.bottom = hasWorkout ? 14 : 6
            button.configuration = config
            button.invalidateIntrinsicContentSize()
        }
        stackView.setNeedsLayout()
        updateSelectionIndicatorFrame(animated: false)
    }

    private func notifySelection() {
        guard selectedIndex >= 0, selectedIndex < days.count else { return }
        onSelectionChanged?(Selection(day: days[selectedIndex], index: selectedIndex))
    }
}
