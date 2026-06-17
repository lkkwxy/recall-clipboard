//
//  HistoryPanelController.swift
//  Recall
//
//  无边框浮层面板：托管 SwiftUI 历史界面。⌥V 或菜单唤起，点击外部 / Esc 收起。
//

import AppKit
import SwiftUI

/// 可成为 key 的无边框面板（默认 borderless 面板不接收键盘，搜索框需要键盘）。
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var panel: FloatingPanel?

    private static let panelWidth: CGFloat = 600
    private static let panelHeight: CGFloat = 480

    init(appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        positionTopCenter(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let root = HistoryView(onCopyAndClose: { [weak self] in self?.hide() },
                               onEscape: { [weak self] in self?.hide() })
            .environmentObject(appState)

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        // 圆角裁切。
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 14
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        return panel
    }

    private func positionTopCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - Self.panelWidth / 2
        let y = visible.maxY - Self.panelHeight - 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // 点击面板外部失去 key → 收起。
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
