//
//  ClipRowView.swift
//  Recall
//
//  历史列表中的单条卡片：文本 / 图片两种形态，悬停显示复制、删除操作。
//

import SwiftUI

struct ClipRowView: View {
    let item: ClipItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                content
                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(cardBackground)
            .contentShape(Rectangle())
            .onTapGesture(perform: onCopy)

            if hovering {
                actionButtons
                    .padding(8)
            }
        }
        .onHover { hovering = $0 }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .text:
            Text(item.preview)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        case .image:
            HStack(spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text("图片 · PNG")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(item.preview) // 尺寸如 1280×720
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var thumbnail: some View {
        let url = appState.store.fileURL(for: item)
        let image = ThumbnailCache.shared.thumbnail(for: url)
        return ZStack(alignment: .topLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 110, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            Text(item.preview)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .padding(4),
            alignment: .topLeading
        )
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            SourceIconView(bundleID: item.sourceBundleID, name: item.sourceApp)
            Text(item.sourceApp ?? "未知来源")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(relativeTime(item.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 操作

    private var actionButtons: some View {
        HStack(spacing: 6) {
            iconButton("doc.on.doc", action: onCopy)
            iconButton("trash", action: onDelete, destructive: true)
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void, destructive: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(destructive ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(.background.opacity(hovering ? 0.9 : 0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(hovering ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06),
                                  lineWidth: hovering ? 1.5 : 1)
            )
    }
}
