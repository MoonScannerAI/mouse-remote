import SwiftUI
import UIKit

/// A hidden `UITextView` that hosts the real iOS system keyboard and turns every edit
/// (typing, autocorrect, predictions, dictation, deletes) into Backspaces + key taps.
///
/// The text always starts with a sentinel space, so Backspace on an "empty" field still
/// produces a range to delete (and therefore a Backspace on the PC).
@MainActor
struct KeyboardCapture: UIViewRepresentable {
    @Binding var isActive: Bool
    let ble: BLEManager
    let modifiers: ModifierState

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: $isActive, ble: ble, modifiers: modifiers)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        // Autocorrect, predictions, smart punctuation, swipe typing: all system defaults.
        textView.delegate = context.coordinator
        textView.text = Coordinator.sentinel
        textView.backgroundColor = .clear
        textView.textColor = .clear
        textView.tintColor = .clear
        textView.keyboardAppearance = .dark
        textView.isScrollEnabled = false
        context.coordinator.resetShadow(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.isActive = $isActive
        context.coordinator.ble = ble
        context.coordinator.modifiers = modifiers
        if isActive && !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isActive && textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        static let sentinel = " "

        var isActive: Binding<Bool>
        var ble: BLEManager
        var modifiers: ModifierState

        /// What we believe the text view contains after every change we've already sent.
        private var shadow = Coordinator.sentinel
        private var maintenanceScheduled = false

        private let trimThreshold = 400   // UTF-16 units
        private let keepAfterTrim = 120   // characters of recent context for autocorrect

        init(isActive: Binding<Bool>, ble: BLEManager, modifiers: ModifierState) {
            self.isActive = isActive
            self.ble = ble
            self.modifiers = modifiers
        }

        func resetShadow(_ textView: UITextView) {
            shadow = textView.text ?? ""
        }

        // MARK: UITextViewDelegate

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Marked (provisional) text is committed later; textViewDidChange syncs it.
            if textView.markedTextRange != nil { return true }

            let current = (textView.text ?? "") as NSString
            guard range.location != NSNotFound, NSMaxRange(range) <= current.length else { return false }

            let removed = current.substring(with: range)
            send(removed: removed, inserted: text)

            if range.location < (Coordinator.sentinel as NSString).length {
                // The edit consumed the sentinel: rebuild the text with a fresh sentinel.
                let rebuilt = Coordinator.sentinel + text
                textView.text = rebuilt
                let end = (rebuilt as NSString).length
                textView.selectedRange = NSRange(location: end, length: 0)
                shadow = rebuilt
                return false
            }

            shadow = current.replacingCharacters(in: range, with: text)
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            let now = textView.text ?? ""
            if now != shadow {
                // Some input path bypassed shouldChangeTextIn (e.g. dictation commit):
                // diff against what we last sent.
                syncByDiff(from: shadow, to: now)
                shadow = now
            }
            scheduleMaintenance(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            scheduleMaintenance(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if isActive.wrappedValue {
                isActive.wrappedValue = false
            }
        }

        // MARK: Sending

        private func send(removed: String, inserted: String) {
            let backspaces = KeyMap.strokes(for: removed).count
            let strokes = KeyMap.strokes(for: inserted)
            // Sticky modifiers apply only to a single keystroke (a typed key or one Backspace),
            // never to autocorrect/prediction rewrites.
            let isSingleKeystroke = backspaces + strokes.count == 1
            let sticky: UInt8 = isSingleKeystroke ? modifiers.consume() : 0

            for _ in 0..<backspaces {
                ble.keyTap(modifiers: sticky, key: HIDKey.backspace)
            }
            for stroke in strokes {
                ble.keyTap(modifiers: stroke.modifiers | sticky, key: stroke.key)
            }
        }

        private func syncByDiff(from old: String, to new: String) {
            let a = Array(old.unicodeScalars)
            let b = Array(new.unicodeScalars)
            var prefix = 0
            while prefix < a.count && prefix < b.count && a[prefix] == b[prefix] {
                prefix += 1
            }
            var removed = String.UnicodeScalarView()
            removed.append(contentsOf: a[prefix...])
            var inserted = String.UnicodeScalarView()
            inserted.append(contentsOf: b[prefix...])
            send(removed: String(removed), inserted: String(inserted))
        }

        // MARK: Buffer maintenance

        /// Runs after the current UIKit text operation finishes, so autocorrect isn't disturbed.
        private func scheduleMaintenance(_ textView: UITextView) {
            guard !maintenanceScheduled else { return }
            maintenanceScheduled = true
            Task { @MainActor [weak self, weak textView] in
                guard let self, let textView else { return }
                self.maintenanceScheduled = false
                self.performMaintenance(textView)
            }
        }

        private func performMaintenance(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            var text = textView.text ?? ""

            // Restore the sentinel if it is somehow gone.
            if !text.hasPrefix(Coordinator.sentinel) {
                text = Coordinator.sentinel + text
                textView.text = text
                shadow = text
            }

            // Trim at a word boundary, keeping recent context for autocorrect.
            if (text as NSString).length > trimThreshold,
               let last = text.last, last.isWhitespace || last.isNewline {
                var keep = String(text.suffix(keepAfterTrim))
                if let space = keep.firstIndex(where: { $0 == " " || $0 == "\n" }) {
                    keep = String(keep[keep.index(after: space)...])
                }
                text = Coordinator.sentinel + keep
                textView.text = text
                shadow = text
            }

            // Keep the caret at the end so every edit maps onto the PC's cursor position.
            let end = (text as NSString).length
            let selection = textView.selectedRange
            if selection.location != end || selection.length != 0 {
                textView.selectedRange = NSRange(location: end, length: 0)
            }
        }
    }
}
