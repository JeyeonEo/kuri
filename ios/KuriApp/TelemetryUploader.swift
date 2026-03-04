import Foundation
import KuriObservability

actor TelemetryUploader {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private var buffer: [PerformanceSample] = []
    private let batchSize = 10

    init(baseURL: URL, session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func record(_ sample: PerformanceSample) {
        buffer.append(sample)
        if buffer.count >= batchSize {
            Task { await flush() }
        }
    }

    func flush() async {
        guard !buffer.isEmpty else { return }
        let samples = buffer
        buffer = []

        var request = URLRequest(url: baseURL.appending(path: "/v1/telemetry/client-performance"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        struct Payload: Encodable {
            let samples: [SamplePayload]
        }
        struct SamplePayload: Encodable {
            let metric: String
            let durationMs: Double
            let timestamp: String
        }

        let formatter = ISO8601DateFormatter()
        let payload = Payload(samples: samples.map { sample in
            SamplePayload(
                metric: sample.metric.rawValue,
                durationMs: sample.durationMs,
                timestamp: formatter.string(from: sample.timestamp)
            )
        })

        request.httpBody = try? JSONEncoder().encode(payload)

        // Best-effort upload; don't throw on failure
        _ = try? await session.data(for: request)
    }
}
