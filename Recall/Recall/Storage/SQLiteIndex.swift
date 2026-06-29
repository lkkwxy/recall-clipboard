//
//  SQLiteIndex.swift
//  Recall
//
//  index.sqlite 的薄封装：只存元数据，搜索/列表走索引不读全部文件。
//  使用系统自带 libsqlite3，无外部依赖。仅供 Storage 层内部使用。
//

import Foundation
import SQLite3

// SQLite 要求拷贝字符串/二进制时用 TRANSIENT，否则可能读到已释放内存。
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteError: Error {
    case open(String)
    case prepare(String)
    case step(String)
}

final class SQLiteIndex {
    private var db: OpaquePointer?

    init(fileURL: URL) throws {
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.open(msg)
        }
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS clips (
            id               TEXT PRIMARY KEY,
            type             INTEGER NOT NULL,
            created_at       REAL    NOT NULL,
            source_app       TEXT,
            source_bundle_id TEXT,
            file_name        TEXT    NOT NULL,
            preview          TEXT    NOT NULL,
            byte_size        INTEGER NOT NULL,
            hash             TEXT    NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_clips_created ON clips(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_clips_hash    ON clips(hash);
        """
        try exec(sql)
    }

    private func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - 写入

    func insert(_ item: ClipItem) throws {
        let sql = """
        INSERT INTO clips (id, type, created_at, source_app, source_bundle_id, file_name, preview, byte_size, hash)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(item.type.rawValue))
        sqlite3_bind_double(stmt, 3, item.createdAt.timeIntervalSince1970)
        bindOptionalText(stmt, 4, item.sourceApp)
        bindOptionalText(stmt, 5, item.sourceBundleID)
        sqlite3_bind_text(stmt, 6, item.fileName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, item.preview, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 8, Int64(item.byteSize))
        sqlite3_bind_text(stmt, 9, item.hash, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    func delete(id: UUID) {
        let sql = "DELETE FROM clips WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    /// 清空所有索引记录。
    func deleteAll() {
        try? exec("DELETE FROM clips;")
    }

    // MARK: - 查询

    /// 最近一条记录的内容哈希，用于跳过连续重复复制。
    func latestHash() -> String? {
        let sql = "SELECT hash FROM clips ORDER BY created_at DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    func count() -> Int {
        scalarInt("SELECT COUNT(*) FROM clips;")
    }

    func totalByteSize() -> Int {
        scalarInt("SELECT COALESCE(SUM(byte_size), 0) FROM clips;")
    }

    /// 通用查询：按类型筛选 + 预览关键词匹配，时间倒序。
    func fetch(query: String?, type: ClipType?, limit: Int) -> [ClipItem] {
        var sql = """
        SELECT id, type, created_at, source_app, source_bundle_id, file_name, preview, byte_size, hash
        FROM clips
        """
        var clauses: [String] = []
        if type != nil { clauses.append("type = ?") }
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !(trimmed?.isEmpty ?? true)
        if hasQuery { clauses.append("preview LIKE ? ESCAPE '\\'") }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY created_at DESC LIMIT ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        if let type {
            sqlite3_bind_int(stmt, idx, Int32(type.rawValue)); idx += 1
        }
        if hasQuery, let trimmed {
            let pattern = "%" + escapeLike(trimmed) + "%"
            sqlite3_bind_text(stmt, idx, pattern, -1, SQLITE_TRANSIENT); idx += 1
        }
        sqlite3_bind_int(stmt, idx, Int32(limit))

        return readRows(stmt)
    }

    func recent(limit: Int) -> [ClipItem] {
        fetch(query: nil, type: nil, limit: limit)
    }

    /// 清理候选：超出条数上限的旧记录 + 早于指定日期的记录。按 id 去重。
    func trimCandidates(keepLimit: Int?, olderThan: Date?) -> [ClipItem] {
        var result: [UUID: ClipItem] = [:]

        if let keepLimit, keepLimit > 0 {
            let sql = """
            SELECT id, type, created_at, source_app, source_bundle_id, file_name, preview, byte_size, hash
            FROM clips ORDER BY created_at DESC LIMIT -1 OFFSET ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(keepLimit))
                for item in readRows(stmt) { result[item.id] = item }
            }
            sqlite3_finalize(stmt)
        }

        if let olderThan {
            let sql = """
            SELECT id, type, created_at, source_app, source_bundle_id, file_name, preview, byte_size, hash
            FROM clips WHERE created_at < ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, olderThan.timeIntervalSince1970)
                for item in readRows(stmt) { result[item.id] = item }
            }
            sqlite3_finalize(stmt)
        }

        return Array(result.values)
    }

    // MARK: - Helpers

    private func scalarInt(_ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func readRows(_ stmt: OpaquePointer?) -> [ClipItem] {
        var items: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(stmt, 0),
                  let id = UUID(uuidString: String(cString: idText)),
                  let type = ClipType(rawValue: Int(sqlite3_column_int(stmt, 1))),
                  let fileName = sqlite3_column_text(stmt, 5),
                  let preview = sqlite3_column_text(stmt, 6),
                  let hash = sqlite3_column_text(stmt, 8)
            else { continue }

            items.append(ClipItem(
                id: id,
                type: type,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                sourceApp: columnText(stmt, 3),
                sourceBundleID: columnText(stmt, 4),
                fileName: String(cString: fileName),
                preview: String(cString: preview),
                byteSize: Int(sqlite3_column_int64(stmt, 7)),
                hash: String(cString: hash)
            ))
        }
        return items
    }

    private func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        sqlite3_column_text(stmt, col).map { String(cString: $0) }
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
