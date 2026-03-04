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
