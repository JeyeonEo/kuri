import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import KuriCore
import KuriStore
import KuriObservability

public protocol SyncScheduler: Sendable {
    func triggerForegroundSync()
    func scheduleRetry(for itemID: UUID, at: Date)
}

public protocol OCRProcessor: Sendable {
    func processImage(at path: String) async throws -> String
}

public protocol CaptureSyncClient: Sendable {
    func sync(item: CaptureItem, databaseId: String) async throws -> SyncResult
}

public struct SyncResult: Sendable {
    public let notionPageID: String

    public init(notionPageID: String) {
        self.notionPageID = notionPageID
    }
}

public final class SyncEngine: Sendable {
    private let repository: CaptureRepository
    private let client: CaptureSyncClient
    private let ocrProcessor: OCRProcessor
    private let scheduler: SyncScheduler
    private let performanceMonitor: PerformanceMonitor
    private let databaseIdProvider: @Sendable () -> String?

    public init(
        repository: CaptureRepository,
        client: CaptureSyncClient,
        ocrProcessor: OCRProcessor,
        scheduler: SyncScheduler,
        performanceMonitor: PerformanceMonitor,
        databaseIdProvider: @escaping @Sendable () -> String?
    ) {
        self.repository = repository
        self.client = client
        self.ocrProcessor = ocrProcessor
        self.scheduler = scheduler
        self.performanceMonitor = performanceMonitor
        self.databaseIdProvider = databaseIdProvider
    }

    public func runPendingSync(limit: Int = 20) async {
        let items = (try? repository.pendingItems(limit: limit)) ?? []
        for item in items {
            await sync(item)
        }
    }

    public func sync(_ item: CaptureItem) async {
        do {
            guard let databaseId = databaseIdProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !databaseId.isEmpty else {
                try await handleFailure(
                    for: item,
                    error: SyncError(code: "missing_database_id", message: "Database is not configured.", isRetryable: false)
                )
                return
            }
            let hydrated = try await prepareForSync(item)
            try repository.markSyncing(id: hydrated.id)
            let span = performanceMonitor.begin(.syncRequest)
            let result = try await client.sync(item: hydrated, databaseId: databaseId)
            _ = span.end()
            try repository.markSynced(id: hydrated.id, notionPageID: result.notionPageID, syncedAt: .now)
        } catch let error as SyncError {
            try? await handleFailure(for: item, error: error)
        } catch {
            try? await handleFailure(
                for: item,
                error: SyncError(code: "unexpected", message: error.localizedDescription, isRetryable: true)
            )
        }
    }

    private func prepareForSync(_ item: CaptureItem) async throws -> CaptureItem {
        guard item.ocrStatus == .pending, let imageLocalPath = item.imageLocalPath else {
            return item
        }
        let span = performanceMonitor.begin(.ocrProcessing)
        let text = try await ocrProcessor.processImage(at: imageLocalPath)
        _ = span.end()
        let title = TitleBuilder.makeTitle(
            sharedText: item.sharedText,
            ocrText: text,
            sourceURL: item.sourceURL,
            date: item.createdAt
        )
        try repository.updateOCR(id: item.id, text: text, title: title)
        return item.updatingOCR(text: text, title: title)
    }

    private func retryDate(retryCount: Int, isRetryable: Bool) -> Date? {
        guard isRetryable, retryCount <= 3 else { return nil }
        switch retryCount {
        case 1:
            return Date().addingTimeInterval(15)
        case 2:
            return Date().addingTimeInterval(120)
        case 3:
            return Date().addingTimeInterval(900)
        default:
            return nil
        }
    }

    private func handleFailure(for item: CaptureItem, error: SyncError) async throws {
        let nextRetryAt = retryDate(retryCount: item.retryCount + 1, isRetryable: error.isRetryable)
        try repository.markFailed(id: item.id, error: error, nextRetryAt: nextRetryAt)
        if let nextRetryAt {
            scheduler.scheduleRetry(for: item.id, at: nextRetryAt)
        }
    }
}

public struct URLSessionCaptureSyncClient: CaptureSyncClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
    }

    public func sync(item: CaptureItem, databaseId: String) async throws -> SyncResult {
        var request = URLRequest(url: baseURL.appending(path: "/v1/captures/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
        request.httpBody = try encoder.encode(CaptureSyncPayload(item: item, databaseId: databaseId))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError(code: "invalid_response", message: "Invalid server response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncError(code: "http_\(httpResponse.statusCode)", message: body, isRetryable: httpResponse.statusCode >= 500)
        }

        let result = try decoder.decode(SyncResponse.self, from: data)
        return SyncResult(notionPageID: result.notionPageId)
    }

    private struct SyncResponse: Decodable {
        let notionPageId: String
    }
}
