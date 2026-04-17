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
        // The strip used to carry a systemUltraThinMaterial blur so it read
        // as a glass pill over the old translucent header card. Now that the
        // header is an opaque secondarySystemBackground, the blur created a
        // nested "box-in-a-box" look. Leaving the view in place (for the
        // contentView/layout) but with no effect, so the strip visually
        // inherits the outer card background.
        let view = UIVisualEffectView(effect: nil)
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
        // `.fill` lets each day button occupy the full strip height so the
        // selection pill (which tracks button frame) scales up with the
        // strip's height constraint.
        view.alignment = .fill
        // `.fillProportionally` sizes each button by its intrinsic content,
        // so when the selected day's title is magnified the button naturally
        // takes more horizontal room and the unselected days compress —
        // leaving breathing space around the magnified date without it
        // wrapping to two lines like `Wed` → `We / d`.
        view.distribution = .fillProportionally
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
            // Dot visibility affects whether the selected-day pill extends
            // downward to cover the indicator, so re-size the pill in the
            // same animation.
            self.updateSelectionIndicatorFrame(animated: false)
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
            stackView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(
                equalTo: blurView.contentView.bottomAnchor, constant: -6),
            stackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
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

        // Use Dynamic Type with UIFontMetrics for accessibility scaling.
        // Kept at caption2 — any bigger and 3-char day names ("Sun", "Wed")
        // can't fit inside their per-button slot and UIKit truncates the
        // second line ("17") away entirely. The selected button compensates
        // by scaling up via transform (see updateButtonMagnification).
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
        button.layer.cornerRadius = 16
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
        // Order matters: swap the button fonts FIRST so .fillProportionally
        // reflows widths based on the new intrinsic content sizes, then let
        // the stack re-layout, THEN position the pill. If the pill is
        // positioned before the relayout it ends up centered on the OLD
        // (narrower) frame of the selected button and looks visibly offset
        // once the selected button grows to its magnified size.
        self.updateButtonMagnification()
        self.stackView.setNeedsLayout()
        self.stackView.layoutIfNeeded()
        self.blurView.contentView.layoutIfNeeded()
        self.updateSelectionIndicatorFrame(animated: animated)
    }

    /// Swaps the selected day button's title font for a larger one and
    /// restores the base font on the others. Uses a font-swap rather than a
    /// CGAffineTransform because UIButton.Configuration recalculates its
    /// title frame based on the label's intrinsic size — transforming the
    /// label breaks the second line ("17") from being measured, which
    /// caused it to vanish entirely from the rendered button.
    private func updateButtonMagnification() {
        for (index, button) in buttons.enumerated() {
            // Defensive: clear any stale transform from earlier versions.
            button.titleLabel?.transform = .identity
            applyTitle(to: button, at: index, magnified: index == selectedIndex)
        }
    }

    private func applyTitle(to button: UIButton, at index: Int, magnified: Bool) {
        guard index < days.count else { return }
        let day = days[index]

        let baseFont = UIFont.preferredFont(forTextStyle: .caption2)
        let font: UIFont
        if magnified {
            // Noticeable size jump + semibold weight so the selected day
            // reads as clearly magnified inside the pill. Works in tandem
            // with the stackView's .fillProportionally distribution — the
            // magnified button claims more horizontal room, so "Wed" etc.
            // don't wrap to two lines.
            let bumped = UIFont.systemFont(
                ofSize: baseFont.pointSize + 6,
                weight: .semibold
            )
            font = UIFontMetrics(forTextStyle: .caption2)
                .scaledFont(for: bumped, maximumPointSize: 26)
        } else {
            font = UIFontMetrics(forTextStyle: .caption2)
                .scaledFont(for: baseFont, maximumPointSize: 18)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 2

        let attributedTitle = NSMutableAttributedString(
            string: "\(day.symbol)\n\(day.shortLabel)",
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: UIColor.label
            ]
        )
        button.configuration?.attributedTitle = AttributedString(attributedTitle)
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

        // Build a content rect that tightly wraps the selected-day label
        // plus the dot if this day shows one. The label's intrinsic size
        // already reflects the magnified font (since applyTitle bumped the
        // font for the selected button), so no extra scaling factor here.
        let labelSize = button.titleLabel?.intrinsicContentSize ?? .zero

        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 10
        let dotExtension: CGFloat = 16 // space for dot + gap when visible

        var pillWidth = labelSize.width + horizontalPadding * 2
        var pillHeight = labelSize.height + verticalPadding * 2
        if index < dotViews.count, !dotViews[index].isHidden {
            pillHeight += dotExtension
        }
        // Cap width/height to the button cell so the pill never spills into
        // neighbors when strip width is tight.
        pillWidth = min(pillWidth, button.frame.width - 4)
        pillHeight = min(pillHeight, button.frame.height - 4)

        let buttonRectInParent = blurView.contentView.convert(button.frame, from: stackView)
        let targetFrame = CGRect(
            x: buttonRectInParent.midX - pillWidth / 2,
            y: buttonRectInParent.midY - pillHeight / 2,
            width: pillWidth,
            height: pillHeight
        )
        // Rounded rectangle rather than a true pill — fixed corner radius
        // keeps the shape squared even when the frame is tall (e.g. when a
        // dot is present), instead of collapsing toward a vertical oval.
        let cornerRadius: CGFloat = 14

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
