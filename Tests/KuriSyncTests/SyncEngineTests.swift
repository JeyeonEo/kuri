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

@Test func syncEngineSchedulesRetryOnServerError() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)
    let created = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: URL(string: "https://threads.net/@kuri/post/5"),
            sharedText: "Retry me",
            memo: "",
            tags: [],
            imagePayloads: []
        )
    )

    let scheduler = TestScheduler()
    let client = FailingTestClient(error: SyncError(code: "http_500", message: "Server error", isRetryable: true))
    let engine = SyncEngine(
        repository: repository,
        client: client,
        ocrProcessor: TestOCR(),
        scheduler: scheduler,
        performanceMonitor: PerformanceMonitor(),
        databaseIdProvider: { "db-1" }
    )

    await engine.sync(created)

    let item = try repository.item(id: created.id)!
    #expect(item.status == .failed)
    #expect(item.retryCount == 1)
    #expect(scheduler.scheduled.count == 1)
    #expect(scheduler.scheduled[0].0 == created.id)
}

@Test func syncEngineDoesNotScheduleRetryForNonRetryableError() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)
    let created = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: URL(string: "https://threads.net/@kuri/post/6"),
            sharedText: "No retry",
            memo: "",
            tags: [],
            imagePayloads: []
        )
    )

    let scheduler = TestScheduler()
    let client = FailingTestClient(error: SyncError(code: "auth_expired", message: "Unauthorized", isRetryable: false))
    let engine = SyncEngine(
        repository: repository,
        client: client,
        ocrProcessor: TestOCR(),
        scheduler: scheduler,
        performanceMonitor: PerformanceMonitor(),
        databaseIdProvider: { "db-1" }
    )

    await engine.sync(created)

    let item = try repository.item(id: created.id)!
    #expect(item.status == .failed)
    #expect(scheduler.scheduled.isEmpty)
}

@Test func syncEngineMarksFailureWhenOCRThrows() async throws {
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
            imagePayloads: [PendingImage(suggestedFilename: "fail.png", data: Data([0x01]))]
        )
    )

    let scheduler = TestScheduler()
    let engine = SyncEngine(
        repository: repository,
        client: TestClient(),
        ocrProcessor: FailingTestOCR(),
        scheduler: scheduler,
        performanceMonitor: PerformanceMonitor(),
        databaseIdProvider: { "db-1" }
    )

    await engine.sync(created)

    let item = try repository.item(id: created.id)!
    #expect(item.status == .failed)
    #expect(item.retryCount == 1)
    #expect(scheduler.scheduled.count == 1)
}

@Test func syncEngineStopsRetryAfterMaxAttempts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)
    let created = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: URL(string: "https://threads.net/@kuri/post/max"),
            sharedText: "Max retries",
            memo: "",
            tags: [],
            imagePayloads: []
        )
    )

    let scheduler = TestScheduler()
    let client = FailingTestClient(error: SyncError(code: "http_500", message: "Server error", isRetryable: true))
    let engine = SyncEngine(
        repository: repository,
        client: client,
        ocrProcessor: TestOCR(),
        scheduler: scheduler,
        performanceMonitor: PerformanceMonitor(),
        databaseIdProvider: { "db-1" }
    )

    // Simulate 4 consecutive failures to exceed the retry limit (max 3)
    for _ in 0..<4 {
        let current = try repository.item(id: created.id)!
        await engine.sync(current)
    }

    let item = try repository.item(id: created.id)!
    #expect(item.status == .failed)
    #expect(item.retryCount == 4)
    // After 3 retries scheduled (at counts 1,2,3), the 4th should not be scheduled
    #expect(scheduler.scheduled.count == 3)
}

private struct FailingTestOCR: OCRProcessor {
    func processImage(at path: String) async throws -> String {
        throw SyncError(code: "ocr_failed", message: "OCR processing failed", isRetryable: true)
    }
}

private final class FailingTestClient: @unchecked Sendable, CaptureSyncClient {
    let error: SyncError

    init(error: SyncError) {
        self.error = error
    }

    func sync(item: CaptureItem, databaseId: String) async throws -> SyncResult {
        throw error
    }
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

#if canImport(Vision) && canImport(CoreGraphics)
import CoreGraphics
import ImageIO

@Test func visionOCRProcessorConformsToProtocol() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // Create a 100x100 white PNG (Vision requires > 2px per dimension)
    let size = 100
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let cgImage = context.makeImage()!

    let imageURL = root.appendingPathComponent("test.png")
    let dest = CGImageDestinationCreateWithURL(imageURL as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cgImage, nil)
    CGImageDestinationFinalize(dest)

    let processor = VisionOCRProcessor()
    let result = try await processor.processImage(at: imageURL.path)
    // A blank white image has no text; result should be empty
    #expect(result.isEmpty)
}
#endif

private final class TestScheduler: @unchecked Sendable, SyncScheduler {
    var scheduled: [(UUID, Date)] = []

    func triggerForegroundSync() {}

    func scheduleRetry(for itemID: UUID, at: Date) {
        scheduled.append((itemID, at))
    }
}
