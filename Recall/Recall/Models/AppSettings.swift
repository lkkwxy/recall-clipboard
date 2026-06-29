//
//  AppSettings.swift
//  Recall
//
//  用户配置，持久化到 UserDefaults。存储路径、保存开关、历史上限、自动清理、外观。
//

import Foundation
import SwiftUI
import Combine

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    /// 保存文件夹根目录。默认 ~/Documents/Recall。
    @Published var rootURL: URL {
        didSet { defaults.set(rootURL.path, forKey: Keys.rootPath) }
    }
    @Published var saveImages: Bool {
        didSet { defaults.set(saveImages, forKey: Keys.saveImages) }
    }
    @Published var saveText: Bool {
        didSet { defaults.set(saveText, forKey: Keys.saveText) }
    }
    /// 历史条数上限，0 表示不限。
    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }
    /// 自动清理天数，0 表示永不清理。
    @Published var autoCleanDays: Int {
        didSet { defaults.set(autoCleanDays, forKey: Keys.autoCleanDays) }
    }
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    /// 被排除的来源应用，命中其 bundleID 的复制不记录。默认空 = 不过滤。
    @Published var excludedApps: [ExcludedApp] {
        didSet { defaults.set(try? JSONEncoder().encode(excludedApps), forKey: Keys.excludedApps) }
    }

    /// 排除名单的 bundleID 集合，供监听时快速命中判断。
    var excludedBundleIDs: Set<String> { Set(excludedApps.map(\.bundleID)) }

    /// 是否曾经启动过。用于区分「全新首次启动」。
    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Keys.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Keys.hasLaunchedBefore) }
    }
    /// 上次启动时记录的系统启动时刻（kern.boottime，秒），用于判断本次是否「开机后第一次启动」。
    var lastSeenBootTime: Double {
        get { defaults.double(forKey: Keys.lastSeenBootTime) }
        set { defaults.set(newValue, forKey: Keys.lastSeenBootTime) }
    }

    init() {
        if let path = defaults.string(forKey: Keys.rootPath) {
            rootURL = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            rootURL = docs.appendingPathComponent("Recall", isDirectory: true)
        }
        saveImages = defaults.object(forKey: Keys.saveImages) as? Bool ?? true
        saveText = defaults.object(forKey: Keys.saveText) as? Bool ?? true
        historyLimit = defaults.object(forKey: Keys.historyLimit) as? Int ?? 500
        autoCleanDays = defaults.object(forKey: Keys.autoCleanDays) as? Int ?? 30
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "")
            ?? .system
        if let data = defaults.data(forKey: Keys.excludedApps),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            excludedApps = apps
        } else {
            excludedApps = []
        }
    }

    private enum Keys {
        static let rootPath = "rootPath"
        static let saveImages = "saveImages"
        static let saveText = "saveText"
        static let historyLimit = "historyLimit"
        static let autoCleanDays = "autoCleanDays"
        static let appearance = "appearance"
        static let excludedApps = "excludedApps"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let lastSeenBootTime = "lastSeenBootTime"
    }
}
