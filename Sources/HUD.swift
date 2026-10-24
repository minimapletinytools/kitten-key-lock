import AppKit
import Foundation

/// Small, non-activating translucent panel that confirms lock/unlock actions.
/// It never becomes key and never steals focus from the app the user is in.
final class HUDController {
    private var panel: NSPanel?
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var generation = 0

    private let panelSize = NSSize(width: 480, height: 124)

    func show(title: String,
              subtitle: String,
              symbol: String,
              duration: TimeInterval = 2.6) {
        generation += 1
        let currentGeneration = generation

        let panel = ensurePanel()
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 30, weight: .medium))

        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.30
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                panel.orderOut(nil)
            })
        }
    }

    // MARK: - Building

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true

        iconView.frame = NSRect(x: 24, y: 35, width: 54, height: 54)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .white
        effect.addSubview(iconView)

        titleLabel.frame = NSRect(x: 94, y: 69, width: 362, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        effect.addSubview(titleLabel)

        subtitleLabel.frame = NSRect(x: 94, y: 26, width: 362, height: 38)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        effect.addSubview(subtitleLabel)

        panel.contentView = effect
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let origin = NSPoint(x: visible.midX - panel.frame.width / 2,
                             y: visible.maxY - panel.frame.height - 24)
        panel.setFrameOrigin(origin)
    }
}
