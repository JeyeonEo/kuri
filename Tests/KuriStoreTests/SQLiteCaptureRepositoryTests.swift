import Foundation
import Testing
@testable import KuriStore
import KuriCore

@Test func savePersistsPendingCaptureAndTags() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: URL(string: "https://threads.net/@kuri/post/1"),
            sharedText: "Fast saves win",
            memo: "check this",
            tags: [" AI ", "pm"],
            imagePayloads: []
        )
    )

    #expect(item.status == .pending)
    #expect(item.tags == ["ai", "pm"])
    #expect(try repository.recentItems(limit: 1).first?.id == item.id)
    let recentTagNames = try repository.recentTags(limit: 5).map(\.name)
    #expect(Set(recentTagNames) == Set(["ai", "pm"]))
}

@Test func imageDraftStartsWithOCRPending() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(
        CaptureDraft(
            sourceApp: .unknown,
            sourceURL: nil,
            sharedText: nil,
            memo: "",
            tags: [],
            imagePayloads: [PendingImage(suggestedFilename: "capture.jpg", data: Data([0x01, 0x02]))]
        )
    )

    #expect(item.ocrStatus == .pending)
    #expect(item.imageLocalPath != nil)
}

@Test func appStateSnapshotCreatesInstallationIDAndPersistsValues() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let initialSnapshot = try repository.snapshot()
    #expect(initialSnapshot.installationID != nil)
    #expect(initialSnapshot.connectionStatus == .disconnected)

    try repository.setString("session-token", for: .sessionToken)
    try repository.setString("db-123", for: .databaseID)
    try repository.setString("KURI Workspace", for: .workspaceName)
    try repository.setString(ConnectionStatus.connected.rawValue, for: .connectionStatus)
    try repository.setString("2026-03-02T01:02:03Z", for: .lastSyncAt)

    let snapshot = try repository.snapshot()
    #expect(snapshot.installationID == initialSnapshot.installationID)
    #expect(snapshot.sessionToken == "session-token")
    #expect(snapshot.databaseID == "db-123")
    #expect(snapshot.workspaceName == "KURI Workspace")
    #expect(snapshot.connectionStatus == .connected)
    #expect(snapshot.lastSyncAt != nil)
}

@Test func pendingItemsExcludesAlreadySyncingEntries() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: URL(string: "https://threads.net/@kuri/post/2"),
            sharedText: "Queued once",
            memo: "",
            tags: [],
            imagePayloads: []
        )
    )
    try repository.markSyncing(id: item.id)

    let pending = try repository.pendingItems(limit: 10)
    #expect(pending.isEmpty)
}

@Test func markSyncedUpdatesStatusAndNotionPageID() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: URL(string: "https://threads.net/@kuri/post/3"),
            sharedText: "Sync me",
            memo: "",
            tags: [],
            imagePayloads: []
        )
    )

    try repository.markSyncing(id: item.id)
    try repository.markSynced(id: item.id, notionPageID: "page-abc", syncedAt: Date())

    let synced = try repository.item(id: item.id)!
    #expect(synced.status == .synced)
    #expect(synced.notionPageID == "page-abc")
    #expect(synced.syncedAt != nil)
}

@Test func markFailedRecordsErrorAndRetryDate() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(
        CaptureDraft(
            sourceApp: .x,
            sourceURL: URL(string: "https://x.com/test/1"),
            sharedText: "Will fail",
            memo: "",
            tags: ["test"],
            imagePayloads: []
        )
    )

    let nextRetry = Date().addingTimeInterval(120)
    try repository.markFailed(
        id: item.id,
        error: SyncError(code: "http_500", message: "Internal server error", isRetryable: true),
        nextRetryAt: nextRetry
    )

    let failed = try repository.item(id: item.id)!
    #expect(failed.status == .failed)
    #expect(failed.lastErrorCode == "http_500")
    #expect(failed.retryCount == 1)
    #expect(failed.nextRetryAt != nil)
}

@Test func updateOCRSetsTextAndNewTitle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(
        CaptureDraft(
            sourceApp: .unknown,
            sourceURL: nil,
            sharedText: nil,
            memo: "",
            tags: [],
            imagePayloads: [PendingImage(suggestedFilename: "img.png", data: Data([0x01]))]
        )
    )
    #expect(item.ocrStatus == .pending)

    try repository.updateOCR(id: item.id, text: "Extracted text", title: "Extracted text")

    let updated = try repository.item(id: item.id)!
    #expect(updated.ocrStatus == .completed)
    #expect(updated.ocrText == "Extracted text")
    #expect(updated.title == "Extracted text")
}

@Test func clearConnectionStateRemovesSessionAndConnectionInfo() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    try repository.setString("session-token", for: .sessionToken)
    try repository.setString("db-123", for: .databaseID)
    try repository.setString("KURI Workspace", for: .workspaceName)
    try repository.setString(ConnectionStatus.connected.rawValue, for: .connectionStatus)

    try repository.setString(nil, for: .sessionToken)
    try repository.setString(nil, for: .databaseID)
    try repository.setString(nil, for: .workspaceName)
    try repository.setString(ConnectionStatus.disconnected.rawValue, for: .connectionStatus)

    let snapshot = try repository.snapshot()
    #expect(snapshot.sessionToken == nil)
    #expect(snapshot.databaseID == nil)
    #expect(snapshot.workspaceName == nil)
    #expect(snapshot.connectionStatus == .disconnected)
    // installationID should survive disconnect
    #expect(snapshot.installationID != nil)
}

@Test func recentTagsIncrementUseCount() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    _ = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: nil,
            sharedText: "First",
            memo: "",
            tags: ["swift"],
            imagePayloads: []
        )
    )
    _ = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: nil,
            sharedText: "Second",
            memo: "",
            tags: ["swift", "ios"],
            imagePayloads: []
        )
    )

    let tags = try repository.recentTags(limit: 10)
    let swiftTag = tags.first { $0.name == "swift" }
    let iosTag = tags.first { $0.name == "ios" }
    #expect(swiftTag?.useCount == 2)
    #expect(iosTag?.useCount == 1)
}

@Test func pendingItemsExcludesFutureRetryItems() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(
        CaptureDraft(
            sourceApp: .threads,
            sourceURL: URL(string: "https://threads.net/@kuri/post/99"),
            sharedText: "Future retry",
            memo: "",
            tags: [],
            imagePayloads: []
        )
    )

    // Mark failed with a future retry date
    let futureRetry = Date().addingTimeInterval(3600) // 1 hour from now
    try repository.markFailed(
        id: item.id,
        error: SyncError(code: "http_500", message: "Server error", isRetryable: true),
        nextRetryAt: futureRetry
    )

    let pending = try repository.pendingItems(limit: 10)
    #expect(pending.isEmpty)
}

@Test func saveAndLoadAuthUserRoundTrips() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    // Initially no auth user
    #expect(try repository.loadAuthUser() == nil)

    let user = AuthUser(
        userId: "user_123",
        appleUserId: "001234.abcdef",
        displayName: "Test User",
        email: "test@privaterelay.appleid.com"
    )
    try repository.saveAuthUser(user)

    let loaded = try repository.loadAuthUser()
    #expect(loaded?.userId == "user_123")
    #expect(loaded?.appleUserId == "001234.abcdef")
    #expect(loaded?.displayName == "Test User")
    #expect(loaded?.email == "test@privaterelay.appleid.com")

    // Clear auth user
    try repository.clearAuthUser()
    #expect(try repository.loadAuthUser() == nil)
}

@Test func allTagsReturnsAllTagsSortedByUseCount() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["swift"], imagePayloads: []))
    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "B", memo: "", tags: ["swift", "ios"], imagePayloads: []))
    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "C", memo: "", tags: ["swift", "ios", "ai"], imagePayloads: []))

    let tags = try repository.allTags()
    #expect(tags.count == 3)
    #expect(tags[0].name == "swift")
    #expect(tags[0].useCount == 3)
    #expect(tags[1].name == "ios")
    #expect(tags[1].useCount == 2)
    #expect(tags[2].name == "ai")
    #expect(tags[2].useCount == 1)
}

@Test func deleteItemRemovesCaptureAndImage() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(
        CaptureDraft(
            sourceApp: .unknown,
            sourceURL: nil,
            sharedText: "Delete me",
            memo: "",
            tags: [],
            imagePayloads: [PendingImage(suggestedFilename: "delete.png", data: Data([0x01]))]
        )
    )
    #expect(item.imageLocalPath != nil)

    try repository.delete(id: item.id)

    #expect(try repository.item(id: item.id) == nil)
    if let imagePath = item.imageLocalPath {
        #expect(!FileManager.default.fileExists(atPath: imagePath))
    }
}

@Test func renameTagUpdatesAllCapturesAndRecentTags() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item1 = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["swift", "ios"], imagePayloads: []))
    let item2 = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "B", memo: "", tags: ["swift"], imagePayloads: []))

    try repository.renameTag("swift", to: "swiftlang")

    let updated1 = try repository.item(id: item1.id)
    let updated2 = try repository.item(id: item2.id)
    #expect(updated1?.tags == ["swiftlang", "ios"])
    #expect(updated2?.tags == ["swiftlang"])

    let allTags = try repository.allTags()
    let tagNames = allTags.map(\.name)
    #expect(tagNames.contains("swiftlang"))
    #expect(!tagNames.contains("swift"))
}

@Test func deleteTagRemovesFromAllCapturesAndRecentTags() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["swift", "ios"], imagePayloads: []))

    try repository.deleteTag("swift")

    let updated = try repository.item(id: item.id)
    #expect(updated?.tags == ["ios"])

    let allTags = try repository.allTags()
    #expect(!allTags.map(\.name).contains("swift"))
    #expect(allTags.map(\.name).contains("ios"))
}

@Test func deleteNonExistentTagIsNoOp() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["swift"], imagePayloads: []))

    try repository.deleteTag("nonexistent")

    let allTags = try repository.allTags()
    #expect(allTags.count == 1)
}

@Test func renameTagToExistingNameMerges() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["dev", "development"], imagePayloads: []))

    try repository.renameTag("dev", to: "development")

    let updated = try repository.item(id: item.id)
    #expect(updated?.tags == ["development"])

    let allTags = try repository.allTags()
    #expect(allTags.count == 1)
    #expect(allTags[0].name == "development")
}
