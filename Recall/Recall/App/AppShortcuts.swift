//
//  AppShortcuts.swift
//  Recall
//
//  全局快捷键定义。底层 Carbon RegisterEventHotKey，无需辅助功能权限。
//

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 唤起历史面板，默认 ⌥V。
    static let toggleHistoryPanel = Self("toggleHistoryPanel", default: .init(.v, modifiers: [.option]))
}
