import Foundation

public enum TitleBuilder {
    public static func makeTitle(sharedText: String?, ocrText: String?, sourceURL: URL?, date: Date) -> String {
        let candidates = [
            sharedText?.firstMeaningfulLine,
            ocrText?.firstMeaningfulLine,
            sourceURL.map { "\($0.host ?? "link") \(Self.fallbackDateFormatter.string(from: date))" }
        ]

        for candidate in candidates {
            if let title = normalized(candidate), !title.isEmpty {
                return title
            }
        }

        return "Saved on \(fallbackDateFormatter.string(from: date))"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let squashedWhitespace = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let noHashOnly = squashedWhitespace.replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noHashOnly.isEmpty else { return nil }
        return String(squashedWhitespace.prefix(80))
    }

    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private extension String {
    var firstMeaningfulLine: String? {
        split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

public extension String {
    func trimmedNilIfEmpty() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
