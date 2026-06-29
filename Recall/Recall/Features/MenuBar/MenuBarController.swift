//
//  MenuBarController.swift
//  Recall
//
//  菜单栏图标 + 下拉菜单：最近 5 条 + 打开历史面板 / 设置 / 退出。
//

import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let onOpenPanel: () -> Void
    private let onOpenSettings: () -> Void
    private var statusItem: NSStatusItem?
    private var recentItems: [ClipItem] = []

    init(appState: AppState, onOpenPanel: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.appState = appState
        self.onOpenPanel = onOpenPanel
        self.onOpenSettings = onOpenSettings
        super.init()
        setup()
    }

    private func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Recall")
        icon?.isTemplate = true
        item.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // 打开菜单前刷新最近记录。
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        recentItems = appState.recentItems(limit: 5)

        let header = NSMenuItem(title: "最近", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if recentItems.isEmpty {
            let empty = NSMenuItem(title: "暂无记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (i, item) in recentItems.enumerated() {
                let mi = NSMenuItem(title: label(for: item), action: #selector(copyRecent(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = i
                mi.image = icon(for: item)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())

        let openPanel = NSMenuItem(title: "打开历史面板", action: #selector(openPanel), keyEquivalent: "v")
        openPanel.keyEquivalentModifierMask = [.option]
        openPanel.target = self
        menu.addItem(openPanel)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func label(for item: ClipItem) -> String {
        switch item.type {
        case .text:
            let oneLine = item.preview.replacingOccurrences(of: "\n", with: " ")
            return String(oneLine.prefix(40))
        case .image:
            return "图片 · \(item.preview)"
        }
    }

    private func icon(for item: ClipItem) -> NSImage? {
        let img = appIcon(bundleID: item.sourceBundleID)
            ?? NSImage(systemSymbolName: item.type == .image ? "photo" : "doc.text", accessibilityDescription: nil)
        img?.size = NSSize(width: 16, height: 16)
        return img
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard recentItems.indices.contains(sender.tag) else { return }
        appState.copy(recentItems[sender.tag])
    }

    @objc private func openPanel() { onOpenPanel() }
    @objc private func openSettings() { onOpenSettings() }
}
