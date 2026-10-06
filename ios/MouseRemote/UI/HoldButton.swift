import SwiftUI
import UIKit

/// UIKit-backed button that reports touch down and touch up separately, so it can be held
/// while other fingers use the touchpad or other buttons.
final class HoldButtonView: UIView {
    var onDown: (@MainActor () -> Void)?
    var onUp: (@MainActor () -> Void)?
    var normalColor = UIColor(white: 0.17, alpha: 1) { didSet { refresh() } }
    var pressedColor = UIColor(white: 0.34, alpha: 1) { didSet { refresh() } }

    let titleLabel = UILabel()
    private var isDown = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isExclusiveTouch = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        titleLabel.textAlignment = .center
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func refresh() {
        backgroundColor = isDown ? pressedColor : normalColor
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isDown else { return }
        isDown = true
        refresh()
        onDown?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release()
    }

    private func release() {
        guard isDown else { return }
        isDown = false
        refresh()
        onUp?()
    }
}

@MainActor
struct HoldButton: UIViewRepresentable {
    let title: String
    var fontSize: CGFloat = 17
    var color: UIColor = UIColor(white: 0.17, alpha: 1)
    var pressedColor: UIColor = UIColor(white: 0.34, alpha: 1)
    let onDown: @MainActor () -> Void
    var onUp: @MainActor () -> Void = {}

    func makeUIView(context: Context) -> HoldButtonView {
        let view = HoldButtonView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: HoldButtonView, context: Context) {
        apply(to: uiView)
    }

    private func apply(to view: HoldButtonView) {
        view.titleLabel.text = title
        view.titleLabel.font = .systemFont(ofSize: fontSize, weight: .semibold)
        view.accessibilityLabel = title
        view.normalColor = color
        view.pressedColor = pressedColor
        view.onDown = onDown
        view.onUp = onUp
    }
}
