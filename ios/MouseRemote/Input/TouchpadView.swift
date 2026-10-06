import SwiftUI
import UIKit

/// Raw-touch touchpad.
/// - 1 finger: move (with acceleration); tap = left click.
/// - 2 fingers: pan = scroll; tap = right click.
/// - Double-tap-and-hold, then drag: left button held until the finger lifts.
final class TouchpadView: UIView {
    weak var ble: BLEManager?
    var pointerSpeed: Double = SettingsDefault.pointerSpeed
    var scrollSpeed: Double = SettingsDefault.scrollSpeed
    var naturalScroll: Bool = SettingsDefault.naturalScroll

    // Tunables.
    private let tapSlop: CGFloat = 10           // pt of movement before a touch counts as a move
    private let tapMaxDuration: TimeInterval = 0.25
    private let doubleTapWindow: TimeInterval = 0.25
    private let doubleTapDistance: CGFloat = 60
    private let scrollPointsPerUnit: Double = 22 // at scroll speed 1.0

    // Gesture state.
    private var activeTouches: [UITouch] = []
    private var gestureStartTime: TimeInterval = 0
    private var maxTouchCount = 0
    private var moved = false
    private var startCentroid: CGPoint = .zero
    private var lastCentroid: CGPoint = .zero
    private var lastTimestamp: TimeInterval = 0
    private var remainderX: Double = 0
    private var remainderY: Double = 0
    private var scrollRemainderV: Double = 0
    private var scrollRemainderH: Double = 0
    private var dragging = false

    // Deferred single-tap click (so a second tap can turn into a drag instead).
    private var pendingClickTimer: Timer?
    private var lastTapEndTime: TimeInterval = 0
    private var lastTapLocation: CGPoint = .zero

    private let hintLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = Palette.uiTouchpadFill
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Palette.uiTouchpadBorder.cgColor

        hintLabel.text = "Tap to click · 2-finger tap for right click\n2 fingers to scroll · double-tap & hold to drag"
        hintLabel.numberOfLines = 2
        hintLabel.textAlignment = .center
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = Palette.uiTextSecondary
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasIdle = activeTouches.isEmpty
        for touch in touches where !activeTouches.contains(touch) {
            activeTouches.append(touch)
        }
        let now = touches.first?.timestamp ?? event?.timestamp ?? 0

        if wasIdle {
            beginGesture(at: centroid(), time: now)
        } else if !moved {
            // Finger count changed before any movement: re-baseline so a 2-finger tap
            // isn't mistaken for a move.
            startCentroid = centroid()
        }
        maxTouchCount = max(maxTouchCount, activeTouches.count)
        if activeTouches.count >= 2 {
            firePendingClick()
        }
        lastCentroid = centroid()
        lastTimestamp = now
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !activeTouches.isEmpty else { return }
        let now = touches.first?.timestamp ?? event?.timestamp ?? lastTimestamp
        let c = centroid()

        if !moved {
            if hypot(c.x - startCentroid.x, c.y - startCentroid.y) > tapSlop {
                moved = true
                lastCentroid = c
                lastTimestamp = now
            }
            return
        }

        let dx = Double(c.x - lastCentroid.x)
        let dy = Double(c.y - lastCentroid.y)
        let dt = max(now - lastTimestamp, 1.0 / 240.0)
        lastCentroid = c
        lastTimestamp = now

        if activeTouches.count == 1 || dragging {
            movePointer(dx: dx, dy: dy, dt: dt)
        } else if activeTouches.count == 2 {
            scroll(dx: dx, dy: dy)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesFinished(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesFinished(touches, cancelled: true)
    }

    private func touchesFinished(_ touches: Set<UITouch>, cancelled: Bool) {
        let now = touches.first?.timestamp ?? lastTimestamp
        activeTouches.removeAll { touches.contains($0) }
        if activeTouches.isEmpty {
            endGesture(time: now, cancelled: cancelled)
        } else {
            lastCentroid = centroid()
            if !moved { startCentroid = lastCentroid }
        }
    }

    // MARK: - Gesture lifecycle

    private func beginGesture(at point: CGPoint, time: TimeInterval) {
        gestureStartTime = time
        maxTouchCount = 0
        moved = false
        startCentroid = point
        lastCentroid = point
        lastTimestamp = time
        remainderX = 0
        remainderY = 0
        scrollRemainderV = 0
        scrollRemainderH = 0

        let isSecondTap = pendingClickTimer != nil
            && time - lastTapEndTime < doubleTapWindow
            && hypot(point.x - lastTapLocation.x, point.y - lastTapLocation.y) < doubleTapDistance
        if isSecondTap {
            // Double-tap-and-hold: press now; released when the finger lifts.
            cancelPendingClick()
            dragging = true
            ble?.setButton(.left, down: true)
            Haptics.click()
        } else {
            firePendingClick()
        }
    }

    private func endGesture(time: TimeInterval, cancelled: Bool) {
        let isTap = !cancelled && !moved && (time - gestureStartTime) < tapMaxDuration

        if dragging {
            dragging = false
            ble?.setButton(.left, down: false)
            if isTap && maxTouchCount == 1 {
                // Quick second tap without movement: complete a double-click.
                ble?.click(.left)
            }
            return
        }

        guard isTap else { return }
        if maxTouchCount == 1 {
            lastTapEndTime = time
            lastTapLocation = startCentroid
            schedulePendingClick()
        } else if maxTouchCount == 2 {
            ble?.click(.right)
            Haptics.click()
        }
    }

    private func schedulePendingClick() {
        pendingClickTimer?.invalidate()
        let timer = Timer(timeInterval: doubleTapWindow, target: self,
                          selector: #selector(pendingClickFired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        pendingClickTimer = timer
    }

    @objc private func pendingClickFired() {
        pendingClickTimer = nil
        ble?.click(.left)
        Haptics.click()
    }

    private func firePendingClick() {
        guard pendingClickTimer != nil else { return }
        cancelPendingClick()
        pendingClickFired()
    }

    private func cancelPendingClick() {
        pendingClickTimer?.invalidate()
        pendingClickTimer = nil
    }

    // MARK: - Motion

    private func movePointer(dx: Double, dy: Double, dt: Double) {
        let velocity = hypot(dx, dy) / dt // pt/s
        // Linear below ~120 pt/s for precision, ramping up to 3.5x for fast flicks.
        let acceleration = 1.0 + min(max(velocity - 120.0, 0) / 600.0, 2.5)
        let gain = 1.6 * pointerSpeed * acceleration
        remainderX += dx * gain
        remainderY += dy * gain
        let ix = Int(remainderX.rounded(.towardZero))
        let iy = Int(remainderY.rounded(.towardZero))
        remainderX -= Double(ix)
        remainderY -= Double(iy)
        if ix != 0 || iy != 0 {
            ble?.move(dx: ix, dy: iy)
        }
    }

    private func scroll(dx: Double, dy: Double) {
        let unit = scrollPointsPerUnit / max(scrollSpeed, 0.1)
        // Wheel: positive = up. Natural: content follows the fingers.
        let v = naturalScroll ? dy : -dy
        let h = naturalScroll ? -dx : dx
        scrollRemainderV += v / unit
        scrollRemainderH += h / unit
        let iv = Int(scrollRemainderV.rounded(.towardZero))
        let ih = Int(scrollRemainderH.rounded(.towardZero))
        scrollRemainderV -= Double(iv)
        scrollRemainderH -= Double(ih)
        if iv != 0 || ih != 0 {
            ble?.scroll(vertical: iv, horizontal: ih)
        }
    }

    private func centroid() -> CGPoint {
        guard !activeTouches.isEmpty else { return lastCentroid }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for touch in activeTouches {
            let p = touch.location(in: self)
            x += p.x
            y += p.y
        }
        let n = CGFloat(activeTouches.count)
        return CGPoint(x: x / n, y: y / n)
    }
}

/// SwiftUI wrapper for `TouchpadView`.
@MainActor
struct Touchpad: UIViewRepresentable {
    let ble: BLEManager
    var pointerSpeed: Double
    var scrollSpeed: Double
    var naturalScroll: Bool

    func makeUIView(context: Context) -> TouchpadView {
        let view = TouchpadView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: TouchpadView, context: Context) {
        apply(to: uiView)
    }

    private func apply(to view: TouchpadView) {
        view.ble = ble
        view.pointerSpeed = pointerSpeed
        view.scrollSpeed = scrollSpeed
        view.naturalScroll = naturalScroll
    }
}
