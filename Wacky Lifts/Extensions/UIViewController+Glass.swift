import UIKit

extension UIViewController {
    struct GlassBackgroundConfiguration {
        var blurStyle: UIBlurEffect.Style = .systemUltraThinMaterial
        var tintColor: UIColor = UIColor.secondarySystemBackground.withAlphaComponent(0.5)
        var cornerRadius: CGFloat = 0
        var addTopHighlight: Bool = true
        var highlightAlpha: CGFloat = 0.18
        var shadowAlpha: CGFloat = 0.12
    }

    /// Adds a liquid glass background view pinned to the controller's root view.
    /// The view is inserted at index 0 and tagged for easy replacement.
    func applyLiquidGlassBackground(configuration: GlassBackgroundConfiguration = .init()) {
        removeLiquidGlassBackground()

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        container.layer.masksToBounds = false
        container.tag = glassBackgroundTag

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: configuration.blurStyle))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.backgroundColor = configuration.tintColor
        blurView.layer.cornerRadius = configuration.cornerRadius
        blurView.layer.cornerCurve = .continuous
        blurView.layer.masksToBounds = configuration.cornerRadius > 0

        container.addSubview(blurView)

        let highlightLayer = CAGradientLayer()
        if configuration.addTopHighlight {
            highlightLayer.colors = [
                UIColor.white.withAlphaComponent(configuration.highlightAlpha).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ]
            highlightLayer.locations = [0.0, 0.6]
            blurView.layer.addSublayer(highlightLayer)
        }

        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = Float(configuration.shadowAlpha)
        container.layer.shadowRadius = 24
        container.layer.shadowOffset = CGSize(width: 0, height: 12)

        view.insertSubview(container, at: 0)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.layoutIfNeeded()
        highlightLayer.frame = blurView.bounds
    }

    /// Removes any previously applied liquid glass background.
    func removeLiquidGlassBackground() {
        view.subviews.first(where: { $0.tag == glassBackgroundTag })?.removeFromSuperview()
    }

    private var glassBackgroundTag: Int { 913_773 }
}
