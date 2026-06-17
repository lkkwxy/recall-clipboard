//
//  HistoryView.swift
//  Recall
//
//  历史面板主界面：搜索框 + 全部/文本/图片筛选 + 卡片列表 + 底栏。
//

import SwiftUI

struct HistoryView: View {
    let onCopyAndClose: () -> Void
    let onEscape: () -> Void

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = HistoryViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            PanelBackground()
            VStack(spacing: 0) {
                searchBar
                filterChips
                Divider().opacity(0.4)
                content
                footer
            }
        }
        .frame(width: 600, height: 480)
        .onAppear {
            vm.configure(appState)
            searchFocused = true
        }
        .onExitCommand(perform: onEscape)
    }

    // MARK: - 搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索剪贴板历史", text: $vm.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 14))
            if vm.hasQuery {
                Button { vm.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    // MARK: - 筛选

    private var filterChips: some View {
        HStack(spacing: 8) {
            chip("全部", type: nil)
            chip("文本", type: .text)
            chip("图片", type: .image)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func chip(_ title: String, type: ClipType?) -> some View {
        let selected = vm.filter == type
        return Button { vm.filter = type } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    selected ? AnyShapeStyle(Color.accentColor)
                             : AnyShapeStyle(Color.primary.opacity(0.07)),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 列表 / 空态

    @ViewBuilder
    private var content: some View {
        if vm.items.isEmpty {
            if vm.hasQuery {
                SearchEmptyView(query: vm.query, onClear: { vm.clearSearch() })
            } else {
                EmptyHistoryView()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.items) { item in
                        ClipRowView(
                            item: item,
                            onCopy: { appState.copy(item); onCopyAndClose() },
                            onDelete: { appState.delete(item) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack {
            Text("共 \(vm.totalCount) 条记录")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button { appState.toggleLightDark() } label: {
                Image(systemName: appState.settings.appearance == .dark ? "moon.fill" : "sun.max.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(Divider().opacity(0.4), alignment: .top)
    }
}
