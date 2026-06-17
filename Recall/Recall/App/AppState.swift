//
//  AppState.swift
//  Recall
//
//  应用级协调者：持有 settings / store / monitor，向 UI 暴露复制、删除、迁移等操作。
//  UI 通过它访问数据，不直接接触 Store。
//

import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    let settings: AppSettings
    private(set) var store: ClipboardStore
    let monitor: ClipboardMonitor

    /// 数据变化计数，面板据此实时刷新列表。
    @Published private(set) var revision = 0

    init(settings: AppSettings, store: ClipboardStore) {
        self.settings = settings
        self.store = store
        self.monitor = ClipboardMonitor(store: store, settings: settings)

        monitor.onCapture = { [weak self] in
            guard let self else { return }
            self.store.enforceLimits(keepLimit: self.settings.historyLimit,
                                     autoCleanDays: self.settings.autoCleanDays)
            self.revision += 1
        }
        monitor.start()
        applyAppearance()
        // 启动时按当前配置清理一次历史。
        store.enforceLimits(keepLimit: settings.historyLimit, autoCleanDays: settings.autoCleanDays)
    }

    // MARK: - 查询

    func items(query: String?, type: ClipType?) -> [ClipItem] {
        store.items(query: query, type: type, limit: 1000)
    }
    func recentItems(limit: Int) -> [ClipItem] { store.recentItems(limit: limit) }
    func itemCount() -> Int { store.itemCount() }
    func totalByteSize() -> Int { store.totalByteSize() }

    // MARK: - 操作

    /// 把历史项写回剪贴板（不会重复入库）。
    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text:
            if let s = store.textContent(of: item) { pb.setString(s, forType: .string) }
        case .image:
            if let data = store.imageData(of: item), let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        }
        monitor.suppressCurrentChange()
    }

    func delete(_ item: ClipItem) {
        store.delete(item)
        revision += 1
    }

    /// 更改保存文件夹（含数据迁移）。失败抛出，调用方负责提示。
    func changeRoot(to newRoot: URL) throws {
        try store.migrate(to: newRoot)
        settings.rootURL = store.rootURL
        revision += 1
    }

    func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    func toggleLightDark() {
        settings.appearance = settings.appearance == .dark ? .light : .dark
        applyAppearance()
    }

    func openStorageFolder() {
        NSWorkspace.shared.open(store.rootURL)
    }
}
