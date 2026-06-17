//
//  ExcludedApp.swift
//  Recall
//
//  被排除的来源应用。命中其 bundleID 的复制不记录。持久化到 UserDefaults。
//

import Foundation

struct ExcludedApp: Codable, Identifiable, Equatable {
    let bundleID: String
    let name: String      // 添加时记录的显示名，应用移走也能展示

    var id: String { bundleID }
}
