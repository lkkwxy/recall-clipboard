//
//  SettingsView.swift
//  Recall
//
//  通用设置：保存位置（含迁移）、保存开关、历史上限、自动清理、占用空间。
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings: AppSettings
    @State private var usedBytes: Int = 0
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    init(settings: AppSettings) {
        self._settings = ObservedObject(wrappedValue: settings)
    }

    private static let historyOptions: [(label: String, value: Int)] =
        [("最近 100 条", 100), ("最近 200 条", 200), ("最近 500 条", 500), ("最近 1000 条", 1000), ("不限", 0)]
    private static let cleanOptions: [(label: String, value: Int)] =
        [("7 天", 7), ("14 天", 14), ("30 天", 30), ("90 天", 90), ("永不", 0)]

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Label(settings.rootURL.path, systemImage: "folder.fill")
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 220, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Button("更改…", action: changeFolder)
                    }
                } label: {
                    Text("保存位置")
                    Text("新复制的内容会保存到此文件夹").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent {
                    KeyboardShortcuts.Recorder(for: .toggleHistoryPanel)
                } label: {
                    Text("唤起历史面板")
                    Text("全局快捷键，任意应用中可用").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("开机时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in setLaunchAtLogin(newValue) }
            }

            Section {
                Toggle("保存图片到本地文件夹", isOn: $settings.saveImages)
                Toggle("保存文本到本地文件夹", isOn: $settings.saveText)
            }

            Section {
                if settings.excludedApps.isEmpty {
                    Text("未排除任何应用，记录全部来源的复制")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedApps) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: icon(for: app.bundleID))
                                .resizable().frame(width: 18, height: 18)
                            Text(app.name)
                            Spacer()
                            Button {
                                settings.excludedApps.removeAll { $0.bundleID == app.bundleID }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("添加应用…", action: addExcludedApps)
            } header: {
                Text("不记录来自这些应用的复制")
            }

            Section {
                Picker("历史上限", selection: $settings.historyLimit) {
                    ForEach(Self.historyOptions, id: \.value) { Text($0.label).tag($0.value) }
                }
                LabeledContent {
                    Picker("", selection: $settings.autoCleanDays) {
                        ForEach(Self.cleanOptions, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    Text("自动清理")
                    Text("超期记录将自动删除").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent {
                    Button("打开文件夹") { appState.openStorageFolder() }
                } label: {
                    Text("已使用 \(byteString(usedBytes)) 本地存储")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
        .navigationTitle("通用")
        .onAppear { recomputeUsage() }
        .onChange(of: settings.historyLimit) { _ in applyCleanup() }
        .onChange(of: settings.autoCleanDays) { _ in applyCleanup() }
    }

    private func addExcludedApps() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "添加"
        panel.message = "选择要排除的应用，来自它们的复制将不被记录"
        guard panel.runModal() == .OK else { return }

        var existing = settings.excludedBundleIDs
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  !existing.contains(bundleID) else { continue }
            let name = FileManager.default.displayName(atPath: url.path)
            settings.excludedApps.append(ExcludedApp(bundleID: bundleID, name: name))
            existing.insert(bundleID)
        }
    }

    /// 由 bundleID 取应用图标；定位不到时退回通用应用图标。
    private func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled  // 回滚到系统真实状态
            let alert = NSAlert()
            alert.messageText = enabled ? "无法开启开机自启动" : "无法关闭开机自启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func applyCleanup() {
        appState.store.enforceLimits(keepLimit: settings.historyLimit, autoCleanDays: settings.autoCleanDays)
        recomputeUsage()
    }

    private func recomputeUsage() {
        usedBytes = appState.totalByteSize()
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择新的保存文件夹，现有记录会迁移过去"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let confirm = NSAlert()
        confirm.messageText = "迁移到新文件夹？"
        confirm.informativeText = "现有记录会复制到\n\(url.path)\n复制成功后删除原文件夹中的数据。"
        confirm.addButton(withTitle: "迁移")
        confirm.addButton(withTitle: "取消")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try appState.changeRoot(to: url)
            recomputeUsage()
        } catch {
            let alert = NSAlert()
            alert.messageText = "迁移失败"
            alert.informativeText = "原数据未改动。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }
}
