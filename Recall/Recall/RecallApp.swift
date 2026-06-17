//
//  RecallApp.swift
//  Recall
//
//  Created by 李坤 on 2026/6/16.
//

import SwiftUI

@main
struct RecallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 菜单栏常驻应用：无主窗口。设置窗口由 AppKit 的 SettingsWindowController
        // 管理（见 AppDelegate），不走 SwiftUI Settings 场景——后者在 LSUIElement
        // 应用里无法可靠打开。这里保留一个空 Settings 场景仅为满足「App 必须有
        // Scene」的要求。
        Settings { EmptyView() }
    }
}
