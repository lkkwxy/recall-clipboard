//
//  HistorySupport.swift
//  Recall
//
//  历史界面共用的小工具：相对时间、来源 App 图标、缩略图缓存、面板背景。
//

import SwiftUI
import AppKit
import ImageIO

// MARK: - 相对时间

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.unitsStyle = .short
    return f
}()

func relativeTime(_ date: Date) -> String {
    relativeFormatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - 来源 App 图标

func appIcon(bundleID: String?) -> NSImage? {
    guard let bundleID,
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

/// 来源 App 小图标；取不到真实图标时用首字母色块兜底。
struct SourceIconView: View {
    let bundleID: String?
    let name: String?

    var body: some View {
        if let icon = appIcon(bundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 14, height: 14)
                .overlay(
                    Text(String(name?.prefix(1) ?? "?"))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}

// MARK: - 缩略图缓存

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    /// 按需生成降采样缩略图并缓存，列表不直接加载原图。
    func thumbnail(for url: URL, maxPixel: CGFloat = 200) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = Self.downsample(url: url, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func downsample(url: URL, maxPixel: CGFloat) -> NSImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

// MARK: - 面板背景（毛玻璃 + 渐变）

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PanelBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color.purple.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
