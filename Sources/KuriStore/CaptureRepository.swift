import Foundation
import SQLite3
import KuriCore

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public protocol CaptureRepository: Sendable {
    func save(_ draft: CaptureDraft) throws -> CaptureItem
    func item(id: UUID) throws -> CaptureItem?
    func pendingItems(limit: Int) throws -> [CaptureItem]
    func recentItems(limit: Int) throws -> [CaptureItem]
    func recentTags(limit: Int) throws -> [RecentTag]
    func allTags() throws -> [RecentTag]
    func markSyncing(id: UUID) throws
    func markSynced(id: UUID, notionPageID: String, syncedAt: Date) throws
    func markFailed(id: UUID, error: SyncError, nextRetryAt: Date?) throws
    func markOCRPending(id: UUID, imageLocalPath: String) throws
    func updateOCR(id: UUID, text: String, title: String) throws
    func delete(id: UUID) throws
    func renameTag(_ oldName: String, to newName: String) throws
    func deleteTag(_ name: String) throws
    func mergeTags(source: String, into target: String) throws
}

public protocol AppStateRepository: Sendable {
    func string(for key: AppStateKey) throws -> String?
    func setString(_ value: String?, for key: AppStateKey) throws
    func snapshot() throws -> AppStateSnapshot
    func saveAuthUser(_ user: AuthUser) throws
    func loadAuthUser() throws -> AuthUser?
    func clearAuthUser() throws
}

public enum AppStateKey: String, Sendable {
    case installationID = "installation_id"
    case sessionToken = "session_token"
    case databaseID = "database_id"
    case workspaceName = "workspace_name"
    case connectionStatus = "connection_status"
    case lastSyncAt = "last_sync_at"
    case authUserId = "auth_user_id"
    case authAppleUserId = "auth_apple_user_id"
    case authDisplayName = "auth_display_name"
    case authEmail = "auth_email"
}

public enum ConnectionStatus: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case actionRequired
}

public struct AppStateSnapshot: Sendable {
    public let installationID: String?
    public let sessionToken: String?
    public let databaseID: String?
    public let workspaceName: String?
    public let connectionStatus: ConnectionStatus
    public let lastSyncAt: Date?

    public init(
        installationID: String?,
        sessionToken: String?,
        databaseID: String?,
        workspaceName: String?,
        connectionStatus: ConnectionStatus,
        lastSyncAt: Date?
    ) {
        self.installationID = installationID
        self.sessionToken = sessionToken
        self.databaseID = databaseID
        self.workspaceName = workspaceName
        self.connectionStatus = connectionStatus
        self.lastSyncAt = lastSyncAt
    }
}

public enum StoreError: Error, LocalizedError {
    case openDatabase(String)
    case sqlite(message: String, code: Int32)
    case prepare(String)
    case step(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case let .openDatabase(path):
            "Failed to open database at \(path)"
        case let .sqlite(message, code):
            "SQLite error \(code): \(message)"
        case let .prepare(query):
            "Failed to prepare query: \(query)"
        case let .step(query):
            "Failed to execute query: \(query)"
        case .notFound:
            "Record not found"
        }
    }
}

public final class SQLiteCaptureRepository: @unchecked Sendable, CaptureRepository, AppStateRepository {
    private let db: OpaquePointer
    private let writerQueue = DispatchQueue(label: "kuri.store.writer", qos: .userInitiated)
    private let imageDirectory: URL
    private let iso8601 = ISO8601DateFormatter()

    public init(databaseURL: URL, imageDirectory: URL) throws {
        self.imageDirectory = imageDirectory
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &handle, flags, nil) != SQLITE_OK {
            throw StoreError.openDatabase(databaseURL.path)
        }
        guard let handle else { throw StoreError.openDatabase(databaseURL.path) }
        self.db = handle
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public func save(_ draft: CaptureDraft) throws -> CaptureItem {
        try writerQueue.sync {
            let itemID = UUID()
            let normalizedTags = draft.tags.map(\.normalizedTag).filter { !$0.isEmpty }
            let imagePath = try persistFirstImage(for: itemID, payloads: draft.imagePayloads)
            let ocrStatus: OCRStatus = imagePath == nil ? .none : .pending
            let title = TitleBuilder.makeTitle(
                sharedText: draft.sharedText,
                ocrText: nil,
                sourceURL: draft.sourceURL,
                date: draft.createdAt
            )
            let item = CaptureItem(
                id: itemID,
                sourceApp: draft.sourceApp,
                sourceURL: draft.sourceURL,
                sharedText: draft.sharedText?.trimmedNilIfEmpty(),
                memo: draft.memo.trimmedNilIfEmpty(),
                tags: normalizedTags,
                ocrText: nil,
                ocrStatus: ocrStatus,
                imageLocalPath: imagePath,
                title: title,
                status: .pending,
                retryCount: 0,
                nextRetryAt: nil,
                lastErrorCode: nil,
                lastErrorMessage: nil,
                notionPageID: nil,
                createdAt: draft.createdAt,
                updatedAt: draft.createdAt,
                syncedAt: nil
            )

            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try insert(item)
                try upsertTags(normalizedTags, usedAt: draft.createdAt)
                try execute("COMMIT TRANSACTION")
                return item
            } catch {
                try? execute("ROLLBACK TRANSACTION")
                throw error
            }
        }
    }

    public func pendingItems(limit: Int) throws -> [CaptureItem] {
        try queryItems(
            """
            SELECT * FROM capture_items
            WHERE status IN ('pending', 'failed')
              AND (next_retry_at IS NULL OR next_retry_at <= ?)
            ORDER BY created_at ASC
            LIMIT ?
            """,
            bind: { stmt in
                try self.bind(date: .now, to: 1, in: stmt)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            }
        )
    }

    public func item(id: UUID) throws -> CaptureItem? {
        try queryItems(
            """
            SELECT * FROM capture_items
            WHERE id = ?
            LIMIT 1
            """,
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            }
        ).first
    }

    public func recentItems(limit: Int) throws -> [CaptureItem] {
        try queryItems(
            """
            SELECT * FROM capture_items
            ORDER BY created_at DESC
            LIMIT ?
            """,
            bind: { stmt in
                sqlite3_bind_int(stmt, 1, Int32(limit))
            }
        )
    }

    public func recentTags(limit: Int) throws -> [RecentTag] {
        let query = """
        SELECT name, last_used_at, use_count
        FROM recent_tags
        ORDER BY last_used_at DESC
        LIMIT ?
        """
        let stmt = try prepare(query)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [RecentTag] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(
                RecentTag(
                    name: String(cString: sqlite3_column_text(stmt, 0)),
                    lastUsedAt: try date(at: 1, stmt: stmt),
                    useCount: Int(sqlite3_column_int(stmt, 2))
                )
            )
        }
        return results
    }

    public func allTags() throws -> [RecentTag] {
        let query = """
        SELECT name, last_used_at, use_count
        FROM recent_tags
        ORDER BY use_count DESC, name ASC
        """
        let stmt = try prepare(query)
        defer { sqlite3_finalize(stmt) }

        var results: [RecentTag] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(
                RecentTag(
                    name: String(cString: sqlite3_column_text(stmt, 0)),
                    lastUsedAt: try date(at: 1, stmt: stmt),
                    useCount: Int(sqlite3_column_int(stmt, 2))
                )
            )
        }
        return results
    }

    public func markSyncing(id: UUID) throws {
        try updateStatus(id: id, status: .syncing, error: nil, nextRetryAt: nil, incrementRetryCount: false)
    }

    public func markSynced(id: UUID, notionPageID: String, syncedAt: Date) throws {
        try writerQueue.sync {
            let query = """
            UPDATE capture_items
            SET status = 'synced',
                notion_page_id = ?,
                synced_at = ?,
                updated_at = ?,
                last_error_code = NULL,
                last_error_message = NULL,
                next_retry_at = NULL
            WHERE id = ?
            """
            try runStatement(query) { stmt in
                sqlite3_bind_text(stmt, 1, notionPageID, -1, SQLITE_TRANSIENT)
                try bind(date: syncedAt, to: 2, in: stmt)
                try bind(date: syncedAt, to: 3, in: stmt)
                sqlite3_bind_text(stmt, 4, id.uuidString, -1, SQLITE_TRANSIENT)
            }
        }
    }

    public func markFailed(id: UUID, error: SyncError, nextRetryAt: Date?) throws {
        try updateStatus(id: id, status: .failed, error: error, nextRetryAt: nextRetryAt, incrementRetryCount: true)
    }

    public func markOCRPending(id: UUID, imageLocalPath: String) throws {
        try writerQueue.sync {
            let query = """
            UPDATE capture_items
            SET ocr_status = 'pending',
                image_local_path = ?,
                updated_at = ?
            WHERE id = ?
            """
            try runStatement(query) { stmt in
                sqlite3_bind_text(stmt, 1, imageLocalPath, -1, SQLITE_TRANSIENT)
                try bind(date: .now, to: 2, in: stmt)
                sqlite3_bind_text(stmt, 3, id.uuidString, -1, SQLITE_TRANSIENT)
            }
        }
    }

    public func updateOCR(id: UUID, text: String, title: String) throws {
        try writerQueue.sync {
            let query = """
            UPDATE capture_items
            SET ocr_text = ?,
                title = ?,
                ocr_status = 'completed',
                updated_at = ?
            WHERE id = ?
            """
            try runStatement(query) { stmt in
                sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
                try bind(date: .now, to: 3, in: stmt)
                sqlite3_bind_text(stmt, 4, id.uuidString, -1, SQLITE_TRANSIENT)
            }
        }
    }

    public func delete(id: UUID) throws {
        try writerQueue.sync {
            // Get image path before deleting
            let fetchItem = try self.item(id: id)
            if let imagePath = fetchItem?.imageLocalPath {
                try? FileManager.default.removeItem(atPath: imagePath)
            }

            let query = "DELETE FROM capture_items WHERE id = ?"
            try runStatement(query) { stmt in
                sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            }
        }
    }

    public func renameTag(_ oldName: String, to newName: String) throws {
        let normalized = newName.normalizedTag
        guard !normalized.isEmpty else { return }
        let oldNormalized = oldName.normalizedTag
        guard oldNormalized != normalized else { return }

        try writerQueue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                // Update tags_json in all capture_items containing the old tag
                let selectQuery = "SELECT id, tags_json FROM capture_items WHERE tags_json LIKE ?"
                let selectStmt = try prepare(selectQuery)
                defer { sqlite3_finalize(selectStmt) }
                let pattern = "%\(oldNormalized)%"
                sqlite3_bind_text(selectStmt, 1, pattern, -1, SQLITE_TRANSIENT)

                var updates: [(String, [String])] = []
                while sqlite3_step(selectStmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(selectStmt, 0))
                    let tagsData = Data(
                        bytes: sqlite3_column_blob(selectStmt, 1),
                        count: Int(sqlite3_column_bytes(selectStmt, 1))
                    )
                    var tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
                    let hadOld = tags.contains(oldNormalized)
                    let hasNew = tags.contains(normalized)
                    if hadOld {
                        if hasNew {
                            tags.removeAll { $0 == oldNormalized }
                        } else if let idx = tags.firstIndex(of: oldNormalized) {
                            tags[idx] = normalized
                        }
                        updates.append((id, tags))
                    }
                }

                let updateQuery = "UPDATE capture_items SET tags_json = ?, updated_at = ? WHERE id = ?"
                for (id, tags) in updates {
                    let stmt = try prepare(updateQuery)
                    let tagsJSON = try JSONEncoder().encode(tags)
                    sqlite3_bind_text(stmt, 1, String(data: tagsJSON, encoding: .utf8), -1, SQLITE_TRANSIENT)
                    try bind(date: Date(), to: 2, in: stmt)
                    sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        sqlite3_finalize(stmt)
                        throw lastError(updateQuery)
                    }
                    sqlite3_finalize(stmt)
                }

                // Update recent_tags: merge use counts if target exists
                let existingStmt = try prepare("SELECT use_count FROM recent_tags WHERE name = ?")
                sqlite3_bind_text(existingStmt, 1, normalized, -1, SQLITE_TRANSIENT)
                let targetExists = sqlite3_step(existingStmt) == SQLITE_ROW
                let targetCount = targetExists ? Int(sqlite3_column_int(existingStmt, 0)) : 0
                sqlite3_finalize(existingStmt)

                let oldStmt = try prepare("SELECT use_count FROM recent_tags WHERE name = ?")
                sqlite3_bind_text(oldStmt, 1, oldNormalized, -1, SQLITE_TRANSIENT)
                let oldCount = sqlite3_step(oldStmt) == SQLITE_ROW ? Int(sqlite3_column_int(oldStmt, 0)) : 0
                sqlite3_finalize(oldStmt)

                // Delete old tag
                let deleteStmt = try prepare("DELETE FROM recent_tags WHERE name = ?")
                sqlite3_bind_text(deleteStmt, 1, oldNormalized, -1, SQLITE_TRANSIENT)
                sqlite3_step(deleteStmt)
                sqlite3_finalize(deleteStmt)

                // Insert or update target tag
                let mergedCount = targetCount + oldCount
                let upsertQuery = """
                INSERT INTO recent_tags (name, last_used_at, use_count) VALUES (?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET use_count = ?
                """
                let upsertStmt = try prepare(upsertQuery)
                sqlite3_bind_text(upsertStmt, 1, normalized, -1, SQLITE_TRANSIENT)
                try bind(date: Date(), to: 2, in: upsertStmt)
                sqlite3_bind_int(upsertStmt, 3, Int32(mergedCount))
                sqlite3_bind_int(upsertStmt, 4, Int32(mergedCount))
                guard sqlite3_step(upsertStmt) == SQLITE_DONE else {
                    sqlite3_finalize(upsertStmt)
                    throw lastError(upsertQuery)
                }
                sqlite3_finalize(upsertStmt)

                try execute("COMMIT TRANSACTION")
            } catch {
                try? execute("ROLLBACK TRANSACTION")
                throw error
            }
        }
    }

    public func mergeTags(source: String, into target: String) throws {
        try renameTag(source, to: target)
    }

    public func deleteTag(_ name: String) throws {
        let normalized = name.normalizedTag
        guard !normalized.isEmpty else { return }

        try writerQueue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let selectQuery = "SELECT id, tags_json FROM capture_items WHERE tags_json LIKE ?"
                let selectStmt = try prepare(selectQuery)
                defer { sqlite3_finalize(selectStmt) }
                let pattern = "%\(normalized)%"
                sqlite3_bind_text(selectStmt, 1, pattern, -1, SQLITE_TRANSIENT)

                var updates: [(String, [String])] = []
                while sqlite3_step(selectStmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(selectStmt, 0))
                    let tagsData = Data(
                        bytes: sqlite3_column_blob(selectStmt, 1),
                        count: Int(sqlite3_column_bytes(selectStmt, 1))
                    )
                    var tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
                    if tags.contains(normalized) {
                        tags.removeAll { $0 == normalized }
                        updates.append((id, tags))
                    }
                }

                let updateQuery = "UPDATE capture_items SET tags_json = ?, updated_at = ? WHERE id = ?"
                for (id, tags) in updates {
                    let stmt = try prepare(updateQuery)
                    let tagsJSON = try JSONEncoder().encode(tags)
                    sqlite3_bind_text(stmt, 1, String(data: tagsJSON, encoding: .utf8), -1, SQLITE_TRANSIENT)
                    try bind(date: Date(), to: 2, in: stmt)
                    sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        sqlite3_finalize(stmt)
                        throw lastError(updateQuery)
                    }
                    sqlite3_finalize(stmt)
                }

                let deleteStmt = try prepare("DELETE FROM recent_tags WHERE name = ?")
                sqlite3_bind_text(deleteStmt, 1, normalized, -1, SQLITE_TRANSIENT)
                sqlite3_step(deleteStmt)
                sqlite3_finalize(deleteStmt)

                try execute("COMMIT TRANSACTION")
            } catch {
                try? execute("ROLLBACK TRANSACTION")
                throw error
            }
        }
    }

    public func string(for key: AppStateKey) throws -> String? {
        let query = """
        SELECT value
        FROM app_state
        WHERE key = ?
        LIMIT 1
        """
        let stmt = try prepare(query)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key.rawValue, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        return optionalString(at: 0, stmt: stmt)
    }

    public func setString(_ value: String?, for key: AppStateKey) throws {
        try writerQueue.sync {
            if let value {
                let query = """
                INSERT INTO app_state (key, value)
                VALUES (?, ?)
                ON CONFLICT(key)
                DO UPDATE SET value = excluded.value
                """
                let stmt = try prepare(query)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, key.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError(query) }
            } else {
                let query = "DELETE FROM app_state WHERE key = ?"
                let stmt = try prepare(query)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, key.rawValue, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError(query) }
            }
        }
    }

    public func snapshot() throws -> AppStateSnapshot {
        var installationID = try string(for: .installationID)
        if installationID == nil {
            installationID = UUID().uuidString
            try setString(installationID, for: .installationID)
        }

        let connectionStatus = ConnectionStatus(
            rawValue: try string(for: .connectionStatus) ?? ""
        ) ?? .disconnected
        let lastSyncAt = try string(for: .lastSyncAt).flatMap(iso8601.date(from:))

        return AppStateSnapshot(
            installationID: installationID,
            sessionToken: try string(for: .sessionToken),
            databaseID: try string(for: .databaseID),
            workspaceName: try string(for: .workspaceName),
            connectionStatus: connectionStatus,
            lastSyncAt: lastSyncAt
        )
    }

    public func saveAuthUser(_ user: AuthUser) throws {
        try setString(user.userId, for: .authUserId)
        try setString(user.appleUserId, for: .authAppleUserId)
        try setString(user.displayName, for: .authDisplayName)
        try setString(user.email, for: .authEmail)
    }

    public func loadAuthUser() throws -> AuthUser? {
        guard let userId = try string(for: .authUserId),
              let appleUserId = try string(for: .authAppleUserId) else {
            return nil
        }
        return AuthUser(
            userId: userId,
            appleUserId: appleUserId,
            displayName: try string(for: .authDisplayName),
            email: try string(for: .authEmail)
        )
    }

    public func clearAuthUser() throws {
        try setString(nil, for: .authUserId)
        try setString(nil, for: .authAppleUserId)
        try setString(nil, for: .authDisplayName)
        try setString(nil, for: .authEmail)
    }

    private func updateStatus(
        id: UUID,
        status: SyncStatus,
        error: SyncError?,
        nextRetryAt: Date?,
        incrementRetryCount: Bool
    ) throws {
        try writerQueue.sync {
            let query = """
            UPDATE capture_items
            SET status = ?,
                retry_count = retry_count + ?,
                last_error_code = ?,
                last_error_message = ?,
                next_retry_at = ?,
                updated_at = ?
            WHERE id = ?
            """
            let stmt = try prepare(query)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, status.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, incrementRetryCount ? 1 : 0)
            bindOptional(error?.code, to: 3, stmt: stmt)
            bindOptional(error?.message, to: 4, stmt: stmt)
            try bind(optionalDate: nextRetryAt, to: 5, in: stmt)
            try bind(date: .now, to: 6, in: stmt)
            sqlite3_bind_text(stmt, 7, id.uuidString, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError(query) }
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS capture_items (
                id TEXT PRIMARY KEY,
                source_app TEXT NOT NULL,
                source_url TEXT,
                shared_text TEXT,
                memo TEXT,
                tags_json TEXT NOT NULL,
                ocr_text TEXT,
                ocr_status TEXT NOT NULL,
                image_local_path TEXT,
                title TEXT NOT NULL,
                status TEXT NOT NULL,
                retry_count INTEGER NOT NULL DEFAULT 0,
                next_retry_at TEXT,
                last_error_code TEXT,
                last_error_message TEXT,
                notion_page_id TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                synced_at TEXT
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS recent_tags (
                name TEXT PRIMARY KEY,
                last_used_at TEXT NOT NULL,
                use_count INTEGER NOT NULL DEFAULT 1
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS app_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_capture_items_status_next_retry ON capture_items(status, next_retry_at)")
        try execute("CREATE INDEX IF NOT EXISTS idx_capture_items_created_at ON capture_items(created_at DESC)")
    }

    private func insert(_ item: CaptureItem) throws {
        let query = """
        INSERT INTO capture_items (
            id, source_app, source_url, shared_text, memo, tags_json, ocr_text, ocr_status,
            image_local_path, title, status, retry_count, next_retry_at, last_error_code,
            last_error_message, notion_page_id, created_at, updated_at, synced_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let stmt = try prepare(query)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, item.sourceApp.rawValue, -1, SQLITE_TRANSIENT)
        bindOptional(item.sourceURL?.absoluteString, to: 3, stmt: stmt)
        bindOptional(item.sharedText, to: 4, stmt: stmt)
        bindOptional(item.memo, to: 5, stmt: stmt)
        let tagsJSON = try String(decoding: JSONEncoder().encode(item.tags), as: UTF8.self)
        sqlite3_bind_text(stmt, 6, tagsJSON, -1, SQLITE_TRANSIENT)
        bindOptional(item.ocrText, to: 7, stmt: stmt)
        sqlite3_bind_text(stmt, 8, item.ocrStatus.rawValue, -1, SQLITE_TRANSIENT)
        bindOptional(item.imageLocalPath, to: 9, stmt: stmt)
        sqlite3_bind_text(stmt, 10, item.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 11, item.status.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 12, Int32(item.retryCount))
        try bind(optionalDate: item.nextRetryAt, to: 13, in: stmt)
        bindOptional(item.lastErrorCode, to: 14, stmt: stmt)
        bindOptional(item.lastErrorMessage, to: 15, stmt: stmt)
        bindOptional(item.notionPageID, to: 16, stmt: stmt)
        try bind(date: item.createdAt, to: 17, in: stmt)
        try bind(date: item.updatedAt, to: 18, in: stmt)
        try bind(optionalDate: item.syncedAt, to: 19, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError(query) }
    }

    private func upsertTags(_ tags: [String], usedAt: Date) throws {
        guard !tags.isEmpty else { return }
        let query = """
        INSERT INTO recent_tags (name, last_used_at, use_count)
        VALUES (?, ?, 1)
        ON CONFLICT(name)
        DO UPDATE SET last_used_at = excluded.last_used_at, use_count = recent_tags.use_count + 1
        """
        for tag in tags {
            let stmt = try prepare(query)
            sqlite3_bind_text(stmt, 1, tag, -1, SQLITE_TRANSIENT)
            try bind(date: usedAt, to: 2, in: stmt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                sqlite3_finalize(stmt)
                throw lastError(query)
            }
            sqlite3_finalize(stmt)
        }
    }

    private func queryItems(_ query: String, bind: (OpaquePointer) throws -> Void) throws -> [CaptureItem] {
        let stmt = try prepare(query)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt)

        var items: [CaptureItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            items.append(try mapItem(stmt))
        }
        return items
    }

    private func mapItem(_ stmt: OpaquePointer) throws -> CaptureItem {
        let tagsBytes = sqlite3_column_bytes(stmt, 5)
        let tagsPointer = sqlite3_column_text(stmt, 5)
        let tagsData = Data(bytes: tagsPointer!, count: Int(tagsBytes))
        let tags = try JSONDecoder().decode([String].self, from: tagsData)
        return CaptureItem(
            id: UUID(uuidString: string(at: 0, stmt: stmt)) ?? UUID(),
            sourceApp: SourceApp(rawValue: string(at: 1, stmt: stmt)) ?? .unknown,
            sourceURL: URL(string: optionalString(at: 2, stmt: stmt) ?? ""),
            sharedText: optionalString(at: 3, stmt: stmt),
            memo: optionalString(at: 4, stmt: stmt),
            tags: tags,
            ocrText: optionalString(at: 6, stmt: stmt),
            ocrStatus: OCRStatus(rawValue: string(at: 7, stmt: stmt)) ?? .none,
            imageLocalPath: optionalString(at: 8, stmt: stmt),
            title: string(at: 9, stmt: stmt),
            status: SyncStatus(rawValue: string(at: 10, stmt: stmt)) ?? .pending,
            retryCount: Int(sqlite3_column_int(stmt, 11)),
            nextRetryAt: try optionalDate(at: 12, stmt: stmt),
            lastErrorCode: optionalString(at: 13, stmt: stmt),
            lastErrorMessage: optionalString(at: 14, stmt: stmt),
            notionPageID: optionalString(at: 15, stmt: stmt),
            createdAt: try date(at: 16, stmt: stmt),
            updatedAt: try date(at: 17, stmt: stmt),
            syncedAt: try optionalDate(at: 18, stmt: stmt)
        )
    }

    private func persistFirstImage(for itemID: UUID, payloads: [PendingImage]) throws -> String? {
        guard let first = payloads.first else { return nil }
        let filename = itemID.uuidString + "-" + first.suggestedFilename
        let url = imageDirectory.appendingPathComponent(filename)
        try first.data.write(to: url, options: .atomic)
        return url.path
    }

    private func execute(_ query: String) throws {
        guard sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK else {
            throw lastError(query)
        }
    }

    private func runStatement(_ query: String, bind: (OpaquePointer) throws -> Void) throws {
        let stmt = try prepare(query)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError(query) }
    }

    private func prepare(_ query: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw lastError(query)
        }
        return stmt
    }

    private func bind(date: Date, to index: Int32, in stmt: OpaquePointer) throws {
        sqlite3_bind_text(stmt, index, iso8601.string(from: date), -1, SQLITE_TRANSIENT)
    }

    private func bind(optionalDate: Date?, to index: Int32, in stmt: OpaquePointer) throws {
        if let optionalDate {
            try bind(date: optionalDate, to: index, in: stmt)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptional(_ value: String?, to index: Int32, stmt: OpaquePointer) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func date(at index: Int32, stmt: OpaquePointer) throws -> Date {
        guard let string = optionalString(at: index, stmt: stmt), let date = iso8601.date(from: string) else {
            throw StoreError.sqlite(message: "Invalid date", code: SQLITE_MISMATCH)
        }
        return date
    }

    private func optionalDate(at index: Int32, stmt: OpaquePointer) throws -> Date? {
        guard let value = optionalString(at: index, stmt: stmt) else { return nil }
        guard let date = iso8601.date(from: value) else {
            throw StoreError.sqlite(message: "Invalid optional date", code: SQLITE_MISMATCH)
        }
        return date
    }

    private func string(at index: Int32, stmt: OpaquePointer) -> String {
        String(cString: sqlite3_column_text(stmt, index))
    }

    private func optionalString(at index: Int32, stmt: OpaquePointer) -> String? {
        guard let pointer = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: pointer)
    }

    private func lastError(_ query: String) -> StoreError {
        StoreError.sqlite(message: "\(query) :: \(String(cString: sqlite3_errmsg(db)))", code: sqlite3_errcode(db))
    }
}

private extension String {
    var normalizedTag: String {
        lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
