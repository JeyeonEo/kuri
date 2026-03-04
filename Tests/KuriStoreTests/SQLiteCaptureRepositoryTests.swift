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
