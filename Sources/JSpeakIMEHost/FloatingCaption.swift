import AppKit
import Foundation

@MainActor
final class FloatingCaptionController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var visual: NSVisualEffectView?

    private let maxChars = 120
    private let padding = CGSize(width: 14, height: 10)

    func hide() {
        panel?.orderOut(nil)
    }

    func update(text: String, anchor: CGPoint?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hide()
            return
        }

        let display = trimmed.count > maxChars ? String(trimmed.prefix(maxChars)) + "…" : trimmed

        let panel = ensurePanel()
        label?.stringValue = display
        layoutToFitText(display)
        reposition(panel: panel, anchor: anchor)
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 64),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let visual = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        visual.autoresizingMask = [.width, .height]
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false

        visual.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: padding.width),
            label.trailingAnchor.constraint(equalTo: visual.trailingAnchor, constant: -padding.width),
            label.topAnchor.constraint(equalTo: visual.topAnchor, constant: padding.height),
            label.bottomAnchor.constraint(equalTo: visual.bottomAnchor, constant: -padding.height),
        ])

        panel.contentView = visual

        self.panel = panel
        self.label = label
        self.visual = visual
        return panel
    }

    private func layoutToFitText(_ text: String) {
        guard let panel, let label, let visual else { return }

        let maxWidth: CGFloat = 520

        let size = label.sizeThatFits(NSSize(width: maxWidth - padding.width * 2, height: 200))
        let width = min(maxWidth, ceil(size.width + padding.width * 2))
        let height = ceil(size.height + padding.height * 2)

        panel.setContentSize(NSSize(width: max(width, 240), height: max(height, 44)))
        visual.frame = NSRect(origin: .zero, size: panel.contentView?.bounds.size ?? .zero)
    }

    private func reposition(panel: NSPanel, anchor: CGPoint?) {
        let screen = NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let size = panel.frame.size
        let fallback = CGPoint(x: visible.midX, y: visible.midY)
        let a = anchor ?? fallback

        var x = a.x
        var y = a.y

        // Prefer above caret.
        x = x - size.width / 2
        y = y + 24

        x = max(visible.minX + 12, min(x, visible.maxX - size.width - 12))
        y = max(visible.minY + 12, min(y, visible.maxY - size.height - 12))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
