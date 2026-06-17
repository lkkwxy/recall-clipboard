//
//  SettingsWindowController.swift
//  Recall
//
//  用 AppKit 窗口承载 SettingsView。
//  SwiftUI 的 `Settings` 场景在菜单栏（LSUIElement）应用里无法可靠打开
//  （macOS 14+ 下只提示 "Please use SettingsLink"），故设置窗口自管。
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if window == nil {
            let root = SettingsView(settings: appState.settings)
                .environmentObject(appState)
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "设置"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.identifier = NSUserInterfaceItemIdentifier("RecallSettingsWindow")
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
