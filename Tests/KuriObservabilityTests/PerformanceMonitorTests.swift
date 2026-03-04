import Foundation
import Testing
@testable import KuriObservability

@Test func spanRecordsDuration() async throws {
    let monitor = PerformanceMonitor()
    let span = monitor.begin(.syncRequest)
    try await Task.sleep(for: .milliseconds(50))
    let sample = span.end()

    #expect(sample.metric == .syncRequest)
    #expect(sample.durationMs >= 40)
    #expect(sample.durationMs < 500)
}

@Test func spanEndReturnsCorrectMetric() {
    let monitor = PerformanceMonitor()
    let span = monitor.begin(.ocrProcessing)
    let sample = span.end()

    #expect(sample.metric == .ocrProcessing)
    #expect(sample.durationMs >= 0)
}
