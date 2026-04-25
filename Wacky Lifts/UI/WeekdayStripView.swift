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

    private let calendar = AppDateCoding.calendar
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
        // `.fillEqually` keeps all button frames identical — so when the
        // selection moves, only the pill animates; button widths don't
        // reflow and drag neighbors around. Proportional sizing was
        // previously tried, but it made intermediate days "fly" during
        // the cross-strip animation.
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
        // `.custom` instead of `.system` — the system button type fades its
        // title on tap, which reads as a visible "blink" when combined with
        // the selection pill's spring animation. With custom, the pill
        // movement provides the tap feedback on its own.
        let button = UIButton(type: .custom)
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
        // With .fillEqually distribution, button frames are fixed — only the
        // pill needs to animate. The font swap happens instantly on all
        // buttons inside performWithoutAnimation so UIButton.Configuration
        // doesn't run its own crossfade, but that's now the only layout
        // change happening and it's invisible under the moving pill.
        updateButtonMagnification()
        updateSelectionIndicatorFrame(animated: animated)
    }

    /// Applies a bold-weight trait to the selected day's title (via the
    /// applyTitle helper) and scales the whole selected button up visually
    /// via CGAffineTransform. Because button.frame stays fixed and only
    /// the visual transform changes, neighbors don't reflow and there's
    /// no competing layout animation with the pill.
    private func updateButtonMagnification() {
        UIView.performWithoutAnimation {
            for (index, button) in buttons.enumerated() {
                button.titleLabel?.transform = .identity
                applyTitle(to: button, at: index, magnified: index == selectedIndex)
            }
        }
        for (index, button) in buttons.enumerated() {
            let scale: CGFloat = index == selectedIndex ? Self.selectedScale : 1.0
            button.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    private static let selectedScale: CGFloat = 1.25

    private func applyTitle(to button: UIButton, at index: Int, magnified: Bool) {
        guard index < days.count else { return }
        let day = days[index]

        // All buttons render their title at the same base font. The visual
        // magnification on the selected day is provided by a CGAffineTransform
        // on the button itself (see updateButtonMagnification) — not by
        // swapping fonts. This keeps UIButton.Configuration's layout stable
        // (no "Fr 17" truncation) and avoids the .fillProportionally
        // reflow that made neighbors "fly" on tap.
        let baseFont = UIFont.preferredFont(forTextStyle: .caption2)
        let font = UIFontMetrics(forTextStyle: .caption2)
            .scaledFont(for: baseFont, maximumPointSize: 18)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 2

        let attributedTitle = NSMutableAttributedString(
            string: "\(day.symbol)\n\(day.shortLabel)",
            attributes: [
                .font: magnified
                    ? (UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(.traitBold) ?? font.fontDescriptor, size: 0))
                    : font,
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

        // Build a content rect that wraps the selected-day label scaled to
        // match the button's CGAffineTransform magnification. Since button
        // transform is visual-only, button.frame stays at the equal-width
        // slice — the pill needs to be explicitly sized for the scaled
        // rendering so it visually hugs the magnified content.
        let labelSize = button.titleLabel?.intrinsicContentSize ?? .zero
        let magnified = labelSize.applying(
            CGAffineTransform(scaleX: Self.selectedScale, y: Self.selectedScale)
        )

        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 10
        let dotExtension: CGFloat = 16 // space for dot + gap when visible

        let pillWidth = magnified.width + horizontalPadding * 2
        var pillHeight = magnified.height + verticalPadding * 2
        if index < dotViews.count, !dotViews[index].isHidden {
            pillHeight += dotExtension * Self.selectedScale
        }

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
