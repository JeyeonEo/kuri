import Foundation
import KuriCore

#if canImport(os)
import os
#endif

public enum PerformanceMetric: String, Codable, Sendable {
    case shareExtensionOpenToInteractive = "share_extension_open_to_interactive_ms"
    case saveTapToLocalCommit = "save_tap_to_local_commit_ms"
    case saveTapToSuccessUI = "save_tap_to_success_ui_ms"
    case mainListFirstPaint = "main_list_first_paint_ms"
    case syncRequest = "sync_request_ms"
    case ocrProcessing = "ocr_processing_ms"
}

public struct PerformanceSample: Codable, Sendable {
    public let metric: PerformanceMetric
    public let durationMs: Double
    public let timestamp: Date

    public init(metric: PerformanceMetric, durationMs: Double, timestamp: Date = .now) {
        self.metric = metric
        self.durationMs = durationMs
        self.timestamp = timestamp
    }
}

public final class PerformanceMonitor: @unchecked Sendable {
    #if canImport(os)
    private let logger = Logger(subsystem: "com.kuri.app", category: "performance")
    #endif

    public init() {}

    public func begin(_ metric: PerformanceMetric) -> Span {
        #if canImport(os)
        return Span(metric: metric) { duration in
            self.logger.info("\(metric.rawValue, privacy: .public)=\(duration, privacy: .public)")
        }
        #else
        return Span(metric: metric) { _ in }
        #endif
    }

    public struct Span: Sendable {
        public let metric: PerformanceMetric
        private let start = ContinuousClock.now
        private let complete: @Sendable (Double) -> Void

        fileprivate init(metric: PerformanceMetric, complete: @escaping @Sendable (Double) -> Void) {
            self.metric = metric
            self.complete = complete
        }

        public func end() -> PerformanceSample {
            let elapsed = start.duration(to: .now).components
            let duration = Double(elapsed.seconds) * 1000
                + Double(elapsed.attoseconds) / 1_000_000_000_000_000
            complete(duration)
            return PerformanceSample(metric: metric, durationMs: duration)
        }
    }
}
