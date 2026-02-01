import AppKit
import Foundation
import ApplicationServices

final class TextInjector {
    func applyActions(_ actions: [[String: Any]], target: AXUIElement? = nil) {
        for action in actions {
            guard let type = action["type"] as? String else { continue }
            switch type {
            case "insert":
                if let text = action["text"] as? String {
                    insertText(text, target: target)
                }
            case "delete_backward":
                let count = action["count"] as? Int ?? 1
                deleteBackward(count: count)
            case "clear":
                clearLine()
            default:
                break
            }
        }
    }

    private func insertText(_ text: String, target: AXUIElement?) {
        NSLog("JSpeakAgent: insert len=\(text.count)")
        guard !text.isEmpty else { return }

        if insertViaAccessibility(text, target: target) {
            NSLog("JSpeakAgent: Inserted via Accessibility")
            return
        }

        NSLog("JSpeakAgent: Accessibility insert failed, falling back to Paste")
        insertViaPaste(text)
    }

    private func insertViaAccessibility(_ text: String, target: AXUIElement?) -> Bool {
        var elements: [AXUIElement] = []
        if let target { elements.append(target) }

        // Also try current focused element in case focus changed.
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        if focusErr == .success, let element = focused {
            elements.append(element as! AXUIElement)
        }

        for axElement in elements {
            // Preferred: replace current selection (or insert at caret) when supported.
            if TextInjector.trySetSelectedText(axElement: axElement, text: text) {
                return true
            }

            // Fallback: update full value using selected range (more widely supported).
            if TextInjector.tryInsertByUpdatingValue(axElement: axElement, text: text) {
                return true
            }
        }

        return false
    }

    private static func trySetSelectedText(axElement: AXUIElement, text: String) -> Bool {
        var settable: DarwinBoolean = false
        let isSettableErr = AXUIElementIsAttributeSettable(axElement, kAXSelectedTextAttribute as CFString, &settable)
        guard isSettableErr == .success, settable.boolValue else {
            return false
        }

        let setErr = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return setErr == .success
    }

    private static func tryInsertByUpdatingValue(axElement: AXUIElement, text: String) -> Bool {
        // Read current value.
        var valueRef: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef)
        guard valueErr == .success, let value = valueRef as? String else {
            return false
        }

        // Read selection range if available.
        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        let selectionRange: CFRange
        if rangeErr == .success, let rangeRef {
            let axValue = (rangeRef as! AXValue)
            if AXValueGetType(axValue) == .cfRange {
                var r = CFRange()
                if AXValueGetValue(axValue, .cfRange, &r) {
                selectionRange = r
                } else {
                    selectionRange = CFRange(location: (value as NSString).length, length: 0)
                }
            } else {
                selectionRange = CFRange(location: (value as NSString).length, length: 0)
            }
        } else {
            selectionRange = CFRange(location: (value as NSString).length, length: 0)
        }

        let nsValue = value as NSString
        let safeLoc = max(0, min(selectionRange.location, nsValue.length))
        let safeLen = max(0, min(selectionRange.length, nsValue.length - safeLoc))
        let nsRange = NSRange(location: safeLoc, length: safeLen)

        let newValue = nsValue.replacingCharacters(in: nsRange, with: text)
        let setValueErr = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, newValue as CFTypeRef)
        guard setValueErr == .success else {
            return false
        }

        // Best-effort: move caret after inserted text.
        var caret = CFRange(location: safeLoc + (text as NSString).length, length: 0)
        if let caretValue = AXValueCreate(.cfRange, &caret) {
            _ = AXUIElementSetAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, caretValue)
        }

        return true
    }

    private func insertViaPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendKey(keyCode: 9, flags: .maskCommand) // Cmd+V

        if let original {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }
        }
    }

    private func deleteBackward(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            sendKey(keyCode: 51, flags: [])
        }
    }

    private func clearLine() {
        sendKey(keyCode: 0, flags: .maskCommand) // Cmd+A
        sendKey(keyCode: 51, flags: []) // Delete
    }

    private func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.005)
    }
}
