//
//  AppDelegate.swift
//  Recall
//
//  菜单栏常驻应用入口：建 Store / 监听 / 面板 / 菜单 / 全局快捷键。
//

import AppKit
import SwiftUI
import Combine
import Carbon
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var appState: AppState?
    private var panelController: HistoryPanelController?
    private var menuController: MenuBarController?
    private var settingsController: SettingsWindowController?

    /// 本次是否由登录项自动拉起（开机自启）。靠启动时的 Apple Event 判定，须在 willFinishLaunching 读取。
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem =
            event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
                == UInt32(keyAELaunchedAsLogInItem)
    }

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

        // 用户手动启动时弹一次面板给明确反馈；开机自启则静默驻留。
        if !launchedAsLoginItem {
            panel.show()
        }
    }
}
