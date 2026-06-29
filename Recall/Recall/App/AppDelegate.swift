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

        if shouldAutoShowOnLaunch(settings: settings) {
            // 延后到运行循环稳定后再弹：后台应用启动瞬间尚未取得激活态，
            // 立即弹会被系统抢焦点而收走，故 show 时给一段免收起宽限期。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak panel] in
                NSApp.activate(ignoringOtherApps: true)
                panel?.show(suppressAutoHide: true)
            }
        }
    }

    /// 是否在启动时自动弹一次主面板。
    /// 登录项自启永远是「开机后第一次启动」，据此与用户手动打开区分：
    /// - 全新首次启动 → 弹（新用户引导）
    /// - 开机后第一次启动且已开启自启 → 视为登录项静默拉起，不弹
    /// - 其余（同一开机周期内再次手动打开、或未开自启时的手动打开）→ 弹
    private func shouldAutoShowOnLaunch(settings: AppSettings) -> Bool {
        let bootTime = systemBootTime()
        let bootChanged = abs(bootTime - settings.lastSeenBootTime) > 1
        let firstEverLaunch = !settings.hasLaunchedBefore
        settings.hasLaunchedBefore = true
        settings.lastSeenBootTime = bootTime

        if firstEverLaunch { return true }
        if bootChanged { return !LaunchAtLogin.isEnabled }
        return true
    }

    /// 系统启动时刻（kern.boottime，秒）。读取失败返回 0。
    private func systemBootTime() -> Double {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return 0 }
        return Double(tv.tv_sec)
    }
}
