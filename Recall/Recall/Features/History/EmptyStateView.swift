//
//  EmptyStateView.swift
//  Recall
//
//  历史面板的两种空态：无任何记录 / 搜索无结果。
//

import SwiftUI

/// 还没有任何剪贴板记录。
struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.5))
            VStack(spacing: 6) {
                Text("还没有剪贴板记录")
                    .font(.system(size: 15, weight: .semibold))
                Text("复制任意文本或图片，它们会自动出现在这里")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("按").font(.system(size: 12)).foregroundStyle(.secondary)
                keyCap("⌥")
                Text("+").font(.system(size: 12)).foregroundStyle(.secondary)
                keyCap("V")
                Text("随时唤起").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keyCap(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .medium))
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.1)))
    }
}

/// 搜索无匹配。
struct SearchEmptyView: View {
    let query: String
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.5))
            VStack(spacing: 6) {
                (Text("未找到「") + Text(query).foregroundColor(.accentColor) + Text("」相关记录"))
                    .font(.system(size: 15, weight: .semibold))
                Text("试试更换关键词，或切换到其他筛选类型")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button("清除搜索", action: onClear)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
