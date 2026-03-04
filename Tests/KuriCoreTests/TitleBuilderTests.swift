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

@Test func titleFallsBackToURLAndDate() {
    let title = TitleBuilder.makeTitle(
        sharedText: "   ",
        ocrText: nil,
        sourceURL: URL(string: "https://threads.net/abc"),
        date: Date(timeIntervalSince1970: 0)
    )

    #expect(title.contains("threads.net"))
}
