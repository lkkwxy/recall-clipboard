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

    /// 在此时刻之前忽略 resignKey 触发的自动收起，避免启动瞬间被系统抢焦点而闪退。
    private var autoHideSuppressedUntil = Date.distantPast

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

    /// suppressAutoHide：启动时自动弹出用，给 0.8s 宽限期忽略系统抢焦点导致的 resignKey / 失活，避免一弹就被收走。
    func show(suppressAutoHide: Bool = false) {
        let panel = panel ?? makePanel()
        self.panel = panel
        if suppressAutoHide {
            autoHideSuppressedUntil = Date().addingTimeInterval(0.8)
            panel.hidesOnDeactivate = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak panel] in
                panel?.hidesOnDeactivate = true
            }
        }
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
        // 启动自动弹出后的宽限期内，忽略系统抢焦点导致的误收起。
        if Date() < autoHideSuppressedUntil { return }
        hide()
    }
}
