import Foundation
import Testing
import KuriCore
import KuriStore
@testable import KuriSync
@testable import KuriObservability

@Test func syncEngineProcessesPendingOCRBeforeSync() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)
    let created = try repository.save(
        CaptureDraft(
            sourceApp: .unknown,
            sourceURL: nil,
            sharedText: nil,
            memo: "",
            tags: [],
            imagePayloads: [PendingImage(suggestedFilename: "capture.png", data: Data([0x01]))]
        )
    )

    let scheduler = TestScheduler()
    let client = TestClient()
    let engine = SyncEngine(
        repository: repository,
        client: client,
        ocrProcessor: TestOCR(),
        scheduler: scheduler,
        performanceMonitor: PerformanceMonitor(),
        databaseIdProvider: { "db-1" }
    )

    await engine.sync(created)

    let item = try repository.recentItems(limit: 1)[0]
    #expect(item.status == .synced)
    #expect(item.ocrStatus == .completed)
    #expect(item.title == "recognized")
    #expect(client.lastText == "recognized")
    #expect(scheduler.scheduled.isEmpty)
}

@Test func syncEngineMarksFailureWhenDatabaseIDIsMissing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)
    let created = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: URL(string: "https://threads.net/@kuri/post/1"),
            sharedText: "Fast saves win",
            memo: "",
            tags: [],
            imagePayloads: []
        )
    )

    let engine = SyncEngine(
        repository: repository,
        client: TestClient(),
        ocrProcessor: TestOCR(),
        scheduler: TestScheduler(),
        performanceMonitor: PerformanceMonitor(),
        databaseIdProvider: { nil }
    )

    await engine.sync(created)

    let item = try repository.recentItems(limit: 1)[0]
    #expect(item.status == .failed)
    #expect(item.lastErrorCode == "missing_database_id")
}

private final class TestClient: @unchecked Sendable, CaptureSyncClient {
    var lastText: String?

    func sync(item: CaptureItem, databaseId: String) async throws -> SyncResult {
        lastText = item.ocrText
        return SyncResult(notionPageID: "page-1")
    }
}

private struct TestOCR: OCRProcessor {
    func processImage(at path: String) async throws -> String {
        "recognized"
    }
}

private final class TestScheduler: @unchecked Sendable, SyncScheduler {
    var scheduled: [(UUID, Date)] = []

    func triggerForegroundSync() {}

    func scheduleRetry(for itemID: UUID, at: Date) {
        scheduled.append((itemID, at))
    }
}
