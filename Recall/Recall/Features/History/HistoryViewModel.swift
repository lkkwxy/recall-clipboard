//
//  HistoryViewModel.swift
//  Recall
//
//  历史面板状态：搜索词、类型筛选、结果列表。数据来自 AppState。
//

import SwiftUI
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var query = ""
    @Published var filter: ClipType?            // nil = 全部
    @Published private(set) var items: [ClipItem] = []

    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    func configure(_ appState: AppState) {
        guard self.appState == nil else { return }
        self.appState = appState

        // 数据变化时重载。
        appState.$revision
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        // 搜索词 / 筛选变化时重载（搜索词去抖）。
        $query
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        $filter
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        reload()
    }

    var totalCount: Int { appState?.itemCount() ?? 0 }
    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func reload() {
        guard let appState else { return }
        items = appState.items(query: hasQuery ? query : nil, type: filter)
    }

    func clearSearch() { query = "" }
}
