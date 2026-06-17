//
//  ClipItem.swift
//  Recall
//
//  索引记录的数据模型。正文/图片落地为文件，这里只承载元数据。
//

import Foundation

enum ClipType: Int {
    case text = 0
    case image = 1
}

struct ClipItem: Identifiable {
    let id: UUID
    let type: ClipType
    let createdAt: Date
    let sourceApp: String?       // 来源 App 名称
    let sourceBundleID: String?  // 来源 App bundle id，用于取图标
    let fileName: String         // 对应 texts/ 或 images/ 下的文件名
    let preview: String          // 文本预览；图片为尺寸描述如 "1280×720"
    let byteSize: Int
    let hash: String             // 内容 SHA-256，用于去重
}
