//
//  ClipboardStore.swift
//  Recall
//
//  唯一的数据出入口：写本地文件 + 维护索引 + 去重 + 查询 + 删除 + 路径迁移 + 清理。
//  UI 层与监听层都只与它交互，不直接碰文件系统或剪贴板。
//

import Foundation
import AppKit
import CryptoKit

final class ClipboardStore {
    private(set) var rootURL: URL
    private var textsURL: URL
    private var imagesURL: URL
    private var index: SQLiteIndex

    /// - Parameter rootURL: 保存文件夹根目录。
    init(rootURL: URL) throws {
        self.rootURL = rootURL
        self.textsURL = rootURL.appendingPathComponent("texts", isDirectory: true)
        self.imagesURL = rootURL.appendingPathComponent("images", isDirectory: true)
        try Self.ensureDirectories(root: rootURL)
        self.index = try SQLiteIndex(fileURL: rootURL.appendingPathComponent("index.sqlite"))
    }

    private static func ensureDirectories(root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("texts"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
    }

    // MARK: - 写入

    /// 保存文本。与最近一条哈希相同则跳过（连续重复复制不入库）。
    func saveText(_ text: String, sourceApp: String?, bundleID: String?) {
        let data = Data(text.utf8)
        let hash = Self.sha256(data)
        guard hash != index.latestHash() else { return }

        let fileName = Self.fileName(hash: hash, ext: "md")
        do {
            try data.write(to: textsURL.appendingPathComponent(fileName))
            try index.insert(ClipItem(
                id: UUID(), type: .text, createdAt: Date(),
                sourceApp: sourceApp, sourceBundleID: bundleID,
                fileName: fileName, preview: Self.textPreview(text),
                byteSize: data.count, hash: hash
            ))
        } catch {
            NSLog("Recall: saveText failed — \(error)")
        }
    }

    /// 保存图片。统一转 PNG 存储并以 PNG 字节做哈希，连续相同图片跳过。
    func saveImage(_ image: NSImage, sourceApp: String?, bundleID: String?) {
        guard let png = Self.pngData(from: image) else {
            NSLog("Recall: saveImage failed — 无法生成 PNG")
            return
        }
        let hash = Self.sha256(png)
        guard hash != index.latestHash() else { return }

        let fileName = Self.fileName(hash: hash, ext: "png")
        let size = image.pixelSize ?? image.size
        do {
            try png.write(to: imagesURL.appendingPathComponent(fileName))
            try index.insert(ClipItem(
                id: UUID(), type: .image, createdAt: Date(),
                sourceApp: sourceApp, sourceBundleID: bundleID,
                fileName: fileName, preview: "\(Int(size.width))×\(Int(size.height))",
                byteSize: png.count, hash: hash
            ))
        } catch {
            NSLog("Recall: saveImage failed — \(error)")
        }
    }

    // MARK: - 查询

    func items(query: String?, type: ClipType?, limit: Int = 500) -> [ClipItem] {
        index.fetch(query: query, type: type, limit: limit)
    }
    func recentItems(limit: Int) -> [ClipItem] { index.recent(limit: limit) }
    func itemCount() -> Int { index.count() }
    func totalByteSize() -> Int { index.totalByteSize() }

    func fileURL(for item: ClipItem) -> URL {
        let dir = item.type == .text ? textsURL : imagesURL
        return dir.appendingPathComponent(item.fileName)
    }

    func textContent(of item: ClipItem) -> String? {
        guard item.type == .text else { return nil }
        return try? String(contentsOf: fileURL(for: item), encoding: .utf8)
    }

    func imageData(of item: ClipItem) -> Data? {
        guard item.type == .image else { return nil }
        return try? Data(contentsOf: fileURL(for: item))
    }

    // MARK: - 删除 / 清理

    func delete(_ item: ClipItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        index.delete(id: item.id)
    }

    /// 清空全部历史：删除 texts/ images/ 下所有正文与图片文件，并清空索引。
    /// 只动本应用在保存文件夹内管理的数据。
    func clearAll() {
        let fm = FileManager.default
        for dir in [textsURL, imagesURL] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in files { try? fm.removeItem(at: url) }
        }
        index.deleteAll()
    }

    /// 按配置清理：超过条数上限的旧记录 + 早于保留天数的记录。
    /// 只删除本应用在保存文件夹内管理的文件。
    func enforceLimits(keepLimit: Int, autoCleanDays: Int) {
        let limit = keepLimit > 0 ? keepLimit : nil
        let cutoff = autoCleanDays > 0
            ? Calendar.current.date(byAdding: .day, value: -autoCleanDays, to: Date())
            : nil
        guard limit != nil || cutoff != nil else { return }
        for item in index.trimCandidates(keepLimit: limit, olderThan: cutoff) {
            delete(item)
        }
    }

    // MARK: - 路径迁移

    /// 把当前保存文件夹迁移到 newRoot。先复制成功再删旧，失败回滚，绝不丢数据。
    func migrate(to newRoot: URL) throws {
        let standardizedOld = rootURL.standardizedFileURL
        let standardizedNew = newRoot.standardizedFileURL
        guard standardizedOld != standardizedNew else { return }

        let fm = FileManager.default
        try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)
        try Self.ensureDirectories(root: newRoot)

        let entries = ["texts", "images", "index.sqlite"]
        var copied: [URL] = []
        do {
            for name in entries {
                let src = rootURL.appendingPathComponent(name)
                let dst = newRoot.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                // texts/ images/ 在 ensureDirectories 已建空目录，逐文件拷贝避免冲突。
                if src.hasDirectoryPath {
                    for file in (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? [] {
                        let target = dst.appendingPathComponent(file.lastPathComponent)
                        try fm.copyItem(at: file, to: target)
                        copied.append(target)
                    }
                } else {
                    if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                    try fm.copyItem(at: src, to: dst)
                    copied.append(dst)
                }
            }
        } catch {
            // 回滚：删掉已复制的内容，保留旧数据不动。
            for url in copied { try? fm.removeItem(at: url) }
            throw error
        }

        // 复制成功 → 切换到新索引，再删旧数据。
        let oldRoot = rootURL
        index = try SQLiteIndex(fileURL: newRoot.appendingPathComponent("index.sqlite"))
        rootURL = newRoot
        textsURL = newRoot.appendingPathComponent("texts", isDirectory: true)
        imagesURL = newRoot.appendingPathComponent("images", isDirectory: true)
        for name in entries {
            try? fm.removeItem(at: oldRoot.appendingPathComponent(name))
        }
    }

    // MARK: - Helpers

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 文件名：时间戳 + 哈希前 4 位，避免冒号（文件名非法）。
    private static func fileName(hash: String, ext: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return "\(fmt.string(from: Date()))-\(hash.prefix(4)).\(ext)"
    }

    private static func textPreview(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(oneLine.prefix(120))
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

private extension NSImage {
    /// 实际像素尺寸（NSImage.size 是点尺寸，Retina 下与像素不一致）。
    var pixelSize: NSSize? {
        guard let rep = representations.first as? NSBitmapImageRep else { return nil }
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
