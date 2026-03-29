import UIKit

final class LiquidGlassView: UIView {
    struct Configuration {
        var blurStyle: UIBlurEffect.Style = .systemUltraThinMaterial
        var cornerRadius: CGFloat = 20
        var strokeColor: UIColor = UIColor.white.withAlphaComponent(0.35)
        var strokeWidth: CGFloat = 1
        var shadowColor: UIColor = UIColor.black.withAlphaComponent(0.18)
        var shadowRadius: CGFloat = 16
        var shadowOffset: CGSize = CGSize(width: 0, height: 8)
        var shadowOpacity: Float = 1
        var glowColor: UIColor = UIColor.white.withAlphaComponent(0.18)
        var glowWidth: CGFloat = 1
        var vibrancyEffect: UIVibrancyEffect? = UIVibrancyEffect(blurEffect: UIBlurEffect(style: .systemUltraThinMaterial))
    }

    private let blurView: UIVisualEffectView
    private let vibrancyView: UIVisualEffectView
    private let strokeLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private var config: Configuration

    init(configuration: Configuration = Configuration()) {
        self.config = configuration
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: configuration.blurStyle))
        self.vibrancyView = UIVisualEffectView(effect: configuration.vibrancyEffect)
        super.init(frame: .zero)
        setup()
        applyConfiguration()
    }

    required init?(coder: NSCoder) {
        self.config = Configuration()
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: config.blurStyle))
        self.vibrancyView = UIVisualEffectView(effect: config.vibrancyEffect)
        super.init(coder: coder)
        setup()
        applyConfiguration()
    }

    func update(configuration: Configuration) {
        self.config = configuration
        blurView.effect = UIBlurEffect(style: configuration.blurStyle)
        vibrancyView.effect = configuration.vibrancyEffect
        setNeedsLayout()
        applyConfiguration()
    }

    func contentView() -> UIView {
        return vibrancyView.contentView
    }

    private func setup() {
        backgroundColor = .clear
        layer.masksToBounds = false

        blurView.translatesAutoresizingMaskIntoConstraints = false
        vibrancyView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(blurView)
        blurView.contentView.addSubview(vibrancyView)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            vibrancyView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            vibrancyView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            vibrancyView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            vibrancyView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor)
        ])

        strokeLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(strokeLayer)

        glowLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(glowLayer)
    }

    private func applyConfiguration() {
        layer.shadowColor = config.shadowColor.cgColor
        layer.shadowOpacity = config.shadowOpacity
        layer.shadowRadius = config.shadowRadius
        layer.shadowOffset = config.shadowOffset

        strokeLayer.strokeColor = config.strokeColor.cgColor
        strokeLayer.lineWidth = config.strokeWidth

        glowLayer.strokeColor = config.glowColor.cgColor
        glowLayer.lineWidth = config.glowWidth
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = config.cornerRadius
        blurView.layer.cornerRadius = radius
        blurView.layer.masksToBounds = true

        let path = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
        strokeLayer.frame = bounds
        strokeLayer.path = path

        glowLayer.frame = bounds
        glowLayer.path = path
        glowLayer.shadowColor = config.glowColor.cgColor
        glowLayer.shadowOpacity = 1
        glowLayer.shadowRadius = 10
        glowLayer.shadowOffset = .zero
    }
}
