import Testing
import Foundation
@testable import KuriCore

@Test func titleUsesSharedTextFirstLine() {
    let title = TitleBuilder.makeTitle(
        sharedText: " Great thread \nBody",
        ocrText: "ocr",
        sourceURL: URL(string: "https://x.com/test"),
        date: Date(timeIntervalSince1970: 0)
    )

    #expect(title == "Great thread")
}

@Test func titleUsesOCRTextWhenSharedTextIsNil() {
    let title = TitleBuilder.makeTitle(
        sharedText: nil,
        ocrText: "OCR 첫 번째 줄\n두 번째 줄",
        sourceURL: URL(string: "https://threads.net/abc"),
        date: Date(timeIntervalSince1970: 0)
    )

    #expect(title == "OCR 첫 번째 줄")
}

@Test func titleFallsBackToURLAndDate() {
    let title = TitleBuilder.makeTitle(
        sharedText: "   ",
        ocrText: nil,
        sourceURL: URL(string: "https://threads.net/abc"),
        date: Date(timeIntervalSince1970: 0)
    )

    #expect(title.contains("threads.net"))
}

// MARK: - SourceApp.detect

@Test func detectSourceAppFromURL() {
    #expect(SourceApp.detect(from: URL(string: "https://threads.net/@user/post/1"), fallbackText: nil) == .threads)
    #expect(SourceApp.detect(from: URL(string: "https://www.instagram.com/p/abc"), fallbackText: nil) == .instagram)
    #expect(SourceApp.detect(from: URL(string: "https://x.com/user/status/123"), fallbackText: nil) == .x)
    #expect(SourceApp.detect(from: URL(string: "https://twitter.com/user/status/123"), fallbackText: nil) == .x)
    #expect(SourceApp.detect(from: URL(string: "https://example.com/article"), fallbackText: nil) == .web)
}

@Test func detectSourceAppFromFallbackText() {
    #expect(SourceApp.detect(from: nil, fallbackText: "Check this threads post") == .threads)
    #expect(SourceApp.detect(from: nil, fallbackText: "From instagram") == .instagram)
    #expect(SourceApp.detect(from: nil, fallbackText: "Saw on twitter") == .x)
    #expect(SourceApp.detect(from: nil, fallbackText: nil) == .unknown)
    #expect(SourceApp.detect(from: nil, fallbackText: "") == .unknown)
}

// MARK: - CaptureSyncPayload

@Test func payloadCombinesSharedTextAndOCRText() {
    let item = CaptureItem(
        id: UUID(),
        sourceApp: .threads,
        sourceURL: URL(string: "https://threads.net/@user/post/1"),
        sharedText: "Shared content",
        memo: "My memo",
        tags: ["ai", "pm"],
        ocrText: "OCR content",
        ocrStatus: .completed,
        imageLocalPath: nil,
        title: "Shared content",
        status: .synced,
        retryCount: 0,
        nextRetryAt: nil,
        lastErrorCode: nil,
        lastErrorMessage: nil,
        notionPageID: "page-1",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        syncedAt: Date(timeIntervalSince1970: 0)
    )

    let payload = CaptureSyncPayload(item: item, databaseId: "db-1")
    #expect(payload.text == "Shared content\n\nOCR content")
    #expect(payload.platform == "Threads")
    #expect(payload.tags == ["ai", "pm"])
    #expect(payload.memo == "My memo")
}

@Test func payloadTextIsNilWhenBothEmpty() {
    let item = CaptureItem(
        id: UUID(),
        sourceApp: .unknown,
        sourceURL: nil,
        sharedText: nil,
        memo: nil,
        tags: [],
        ocrText: nil,
        ocrStatus: .none,
        imageLocalPath: nil,
        title: "Saved",
        status: .pending,
        retryCount: 0,
        nextRetryAt: nil,
        lastErrorCode: nil,
        lastErrorMessage: nil,
        notionPageID: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        syncedAt: nil
    )

    let payload = CaptureSyncPayload(item: item, databaseId: "db-1")
    #expect(payload.text == nil)
}
