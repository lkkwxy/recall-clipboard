//
//  AppDelegate.swift
//  Recall
//
//  菜单栏常驻应用入口：建 Store / 监听 / 面板 / 菜单 / 全局快捷键。
//

import AppKit
import SwiftUI
import Combine
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var appState: AppState?
    private var panelController: HistoryPanelController?
    private var menuController: MenuBarController?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        let store: ClipboardStore
        do {
            store = try ClipboardStore(rootURL: settings.rootURL)
        } catch {
            NSLog("Recall: 初始化存储失败 — \(error)")
            return
        }

        let state = AppState(settings: settings, store: store)
        self.appState = state

        let panel = HistoryPanelController(appState: state)
        self.panelController = panel
        let settingsController = SettingsWindowController(appState: state)
        self.settingsController = settingsController
        self.menuController = MenuBarController(
            appState: state,
            onOpenPanel: { [weak panel] in panel?.show() },
            onOpenSettings: { [weak settingsController] in settingsController?.show() }
        )

        KeyboardShortcuts.onKeyUp(for: .toggleHistoryPanel) { [weak panel] in
            panel?.toggle()
        }
    }
}
