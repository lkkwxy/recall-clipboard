//
//  SettingsView.swift
//  Recall
//
//  通用设置：保存位置（含迁移）、保存开关、历史上限、自动清理、占用空间。
//

import SwiftUI
import AppKit
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings: AppSettings
    @State private var usedBytes: Int = 0

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
                Toggle("保存图片到本地文件夹", isOn: $settings.saveImages)
                Toggle("保存文本到本地文件夹", isOn: $settings.saveText)
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
