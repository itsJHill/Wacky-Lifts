import UIKit

extension UIView {
    @discardableResult
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            other.trailingAnchor.constraint(equalTo: trailingAnchor, constant: insets.right),
            other.bottomAnchor.constraint(equalTo: bottomAnchor, constant: insets.bottom)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    @discardableResult
    func constrainSize(_ size: CGSize) -> [NSLayoutConstraint] {
        translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    @discardableResult
    func constrainWidth(_ width: CGFloat) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = widthAnchor.constraint(equalToConstant: width)
        constraint.isActive = true
        return constraint
    }

    @discardableResult
    func constrainHeight(_ height: CGFloat) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = heightAnchor.constraint(equalToConstant: height)
        constraint.isActive = true
        return constraint
    }

    @discardableResult
    func centerInSuperview() -> [NSLayoutConstraint] {
        guard let superview else { return [] }
        translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            centerXAnchor.constraint(equalTo: superview.centerXAnchor),
            centerYAnchor.constraint(equalTo: superview.centerYAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    @discardableResult
    func centerXInSuperview() -> NSLayoutConstraint? {
        guard let superview else { return nil }
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = centerXAnchor.constraint(equalTo: superview.centerXAnchor)
        constraint.isActive = true
        return constraint
    }

    @discardableResult
    func centerYInSuperview() -> NSLayoutConstraint? {
        guard let superview else { return nil }
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = centerYAnchor.constraint(equalTo: superview.centerYAnchor)
        constraint.isActive = true
        return constraint
    }

    @discardableResult
    func pinToSafeArea(of other: UIView, insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        translatesAutoresizingMaskIntoConstraints = false
        let guide = other.safeAreaLayoutGuide
        let constraints = [
            topAnchor.constraint(equalTo: guide.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: insets.left),
            guide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: insets.right),
            guide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: insets.bottom)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }
}
