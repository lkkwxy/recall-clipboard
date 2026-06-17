//
//  ClipboardMonitor.swift
//  Recall
//
//  定时轮询 NSPasteboard.changeCount（系统无剪贴板变化通知）。
//  捕获到新内容 → 识别类型 → 交给 Store。去重由 Store 按内容哈希负责。
//

import AppKit
import UniformTypeIdentifiers

final class ClipboardMonitor {
    private let store: ClipboardStore
    private let settings: AppSettings
    private var lastChangeCount: Int
    private var timer: Timer?

    /// 捕获到新内容后回调（主线程），用于刷新面板/触发清理。
    var onCapture: (() -> Void)?

    // 密码管理器等敏感内容会标记此 UTI，命中时跳过不记录（隐私底线）。
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        // 0.5s：响应足够快，CPU 占用可忽略。
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 应用主动写回剪贴板后调用：把当前 changeCount 记为已处理，
    /// 下一次轮询就不会把我们自己写回的内容再记一条。
    func suppressCurrentChange() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // 隐私底线：敏感内容直接跳过。
        if pb.types?.contains(Self.concealedType) == true { return }

        let app = NSWorkspace.shared.frontmostApplication
        let sourceApp = app?.localizedName
        let bundleID = app?.bundleIdentifier

        // 优先级：图片 > 文本（图片复制有时会同时带文件名文本）。
        if settings.saveImages, let image = readImage(from: pb) {
            store.saveImage(image, sourceApp: sourceApp, bundleID: bundleID)
            onCapture?()
        } else if settings.saveText,
                  let text = pb.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.saveText(text, sourceApp: sourceApp, bundleID: bundleID)
            onCapture?()
        }
    }

    /// 从剪贴板读取图片。
    /// 复制的是文件时（Finder 里 Cmd+C），剪贴板里的位图是文件的通用类型图标而非内容，
    /// 因此只认图片文件的真实内容，绝不回退去读图标位图（否则连 .txt 等非图片文件的图标也会被存）。
    /// 只有在完全没有文件 URL 时（截图、从浏览器/预览复制）才读原始位图数据。
    private func readImage(from pb: NSPasteboard) -> NSImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            guard let url = urls.first(where: { isImageFile($0) }) else { return nil }
            return NSImage(contentsOf: url)
        }
        for type in [NSPasteboard.PasteboardType.tiff, .png] {
            if let data = pb.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    private func isImageFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) ?? false
    }
}
