import UIKit

enum KuriTypography {
    static let heroTitle = UIFont.systemFont(ofSize: 24, weight: .bold)
    static let sectionLabel = UIFont.systemFont(ofSize: 11, weight: .bold)
    static let body = UIFont.systemFont(ofSize: 16, weight: .medium)
    static let bodySmall = UIFont.systemFont(ofSize: 14, weight: .medium)
    static let caption = UIFont.systemFont(ofSize: 12, weight: .medium)
    static let mono = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let button = UIFont.systemFont(ofSize: 15, weight: .bold)

    static func uppercase(_ text: String, font: UIFont, color: UIColor, kern: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: kern
            ]
        )
    }
}
