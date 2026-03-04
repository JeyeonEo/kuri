import Foundation

public enum SourceApp: String, Codable, CaseIterable, Sendable {
    case threads
    case instagram
    case x
    case safari
    case web
    case unknown

    public var notionValue: String {
        switch self {
        case .threads: "Threads"
        case .instagram: "Instagram"
        case .x: "X"
        case .safari, .web: "Web"
        case .unknown: "Unknown"
        }
    }

    public static func detect(from url: URL?, fallbackText: String?) -> SourceApp {
        if let host = url?.host?.lowercased() {
            if host.contains("threads.net") { return .threads }
            if host.contains("instagram.com") { return .instagram }
            if host.contains("x.com") || host.contains("twitter.com") { return .x }
            return .web
        }

        let text = fallbackText?.lowercased() ?? ""
        if text.contains("threads") { return .threads }
        if text.contains("instagram") { return .instagram }
        if text.contains("twitter") || text.contains("x.com") { return .x }
        if text.isEmpty { return .unknown }
        return .web
    }
}

public enum OCRStatus: String, Codable, Sendable {
    case none
    case pending
    case completed
    case failed
}

public enum SyncStatus: String, Codable, Sendable {
    case pending
    case syncing
    case synced
    case failed
}

public struct PendingImage: Codable, Hashable, Sendable {
    public let suggestedFilename: String
    public let data: Data

    public init(suggestedFilename: String, data: Data) {
        self.suggestedFilename = suggestedFilename
        self.data = data
    }
}

public struct CaptureDraft: Sendable {
    public let sourceApp: SourceApp
    public let sourceURL: URL?
    public let sharedText: String?
    public let memo: String
    public let tags: [String]
    public let imagePayloads: [PendingImage]
    public let createdAt: Date

    public init(
        sourceApp: SourceApp,
        sourceURL: URL?,
        sharedText: String?,
        memo: String,
        tags: [String],
        imagePayloads: [PendingImage],
        createdAt: Date = .now
    ) {
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.sharedText = sharedText
        self.memo = memo
        self.tags = tags
        self.imagePayloads = imagePayloads
        self.createdAt = createdAt
    }
}

public struct CaptureItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sourceApp: SourceApp
    public let sourceURL: URL?
    public let sharedText: String?
    public let memo: String?
    public let tags: [String]
    public let ocrText: String?
    public let ocrStatus: OCRStatus
    public let imageLocalPath: String?
    public let title: String
    public let status: SyncStatus
    public let retryCount: Int
    public let nextRetryAt: Date?
    public let lastErrorCode: String?
    public let lastErrorMessage: String?
    public let notionPageID: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let syncedAt: Date?

    public init(
        id: UUID,
        sourceApp: SourceApp,
        sourceURL: URL?,
        sharedText: String?,
        memo: String?,
        tags: [String],
        ocrText: String?,
        ocrStatus: OCRStatus,
        imageLocalPath: String?,
        title: String,
        status: SyncStatus,
        retryCount: Int,
        nextRetryAt: Date?,
        lastErrorCode: String?,
        lastErrorMessage: String?,
        notionPageID: String?,
        createdAt: Date,
        updatedAt: Date,
        syncedAt: Date?
    ) {
        self.id = id
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.sharedText = sharedText
        self.memo = memo
        self.tags = tags
        self.ocrText = ocrText
        self.ocrStatus = ocrStatus
        self.imageLocalPath = imageLocalPath
        self.title = title
        self.status = status
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
        self.notionPageID = notionPageID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
    }
}

public extension CaptureItem {
    func updatingOCR(text: String, title: String) -> CaptureItem {
        CaptureItem(
            id: id,
            sourceApp: sourceApp,
            sourceURL: sourceURL,
            sharedText: sharedText,
            memo: memo,
            tags: tags,
            ocrText: text,
            ocrStatus: .completed,
            imageLocalPath: imageLocalPath,
            title: title,
            status: status,
            retryCount: retryCount,
            nextRetryAt: nextRetryAt,
            lastErrorCode: lastErrorCode,
            lastErrorMessage: lastErrorMessage,
            notionPageID: notionPageID,
            createdAt: createdAt,
            updatedAt: .now,
            syncedAt: syncedAt
        )
    }
}

public struct RecentTag: Codable, Hashable, Sendable {
    public let name: String
    public let lastUsedAt: Date
    public let useCount: Int

    public init(name: String, lastUsedAt: Date, useCount: Int) {
        self.name = name
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

public struct SyncError: Error, Codable, Sendable {
    public let code: String
    public let message: String
    public let isRetryable: Bool

    public init(code: String, message: String, isRetryable: Bool = true) {
        self.code = code
        self.message = message
        self.isRetryable = isRetryable
    }
}

public struct CaptureSyncPayload: Codable, Sendable {
    public let clientItemId: UUID
    public let databaseId: String
    public let title: String
    public let sourceURL: URL?
    public let platform: String
    public let tags: [String]
    public let memo: String?
    public let text: String?
    public let status: String
    public let capturedAt: Date

    public init(item: CaptureItem, databaseId: String) {
        self.clientItemId = item.id
        self.databaseId = databaseId
        self.title = item.title
        self.sourceURL = item.sourceURL
        self.platform = item.sourceApp.notionValue
        self.tags = item.tags
        self.memo = item.memo
        self.text = [item.sharedText, item.ocrText]
            .compactMap { $0?.trimmedNilIfEmpty() }
            .joined(separator: "\n\n")
            .trimmedNilIfEmpty()
        self.status = "Synced"
        self.capturedAt = item.createdAt
    }
}
