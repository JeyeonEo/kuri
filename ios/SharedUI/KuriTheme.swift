import UIKit

enum KuriTheme {
    static let surfacePrimary = UIColor(red: 241 / 255, green: 238 / 255, blue: 231 / 255, alpha: 1)
    static let surfaceSecondary = UIColor(red: 231 / 255, green: 227 / 255, blue: 218 / 255, alpha: 1)
    static let appBackground = UIColor(red: 247 / 255, green: 244 / 255, blue: 238 / 255, alpha: 1)
    static let inkPrimary = UIColor(red: 58 / 255, green: 54 / 255, blue: 49 / 255, alpha: 1)
    static let inkMuted = UIColor(red: 150 / 255, green: 144 / 255, blue: 135 / 255, alpha: 1)
    static let borderSubtle = UIColor(red: 204 / 255, green: 198 / 255, blue: 189 / 255, alpha: 1)
    static let overlayDim = UIColor(white: 0, alpha: 0.64)
    static let accentSuccess = UIColor(red: 52 / 255, green: 181 / 255, blue: 91 / 255, alpha: 1)
    static let accentPending = UIColor(red: 92 / 255, green: 108 / 255, blue: 126 / 255, alpha: 1)
    static let accentWarning = UIColor(red: 188 / 255, green: 132 / 255, blue: 44 / 255, alpha: 1)
    static let accentError = UIColor(red: 176 / 255, green: 52 / 255, blue: 46 / 255, alpha: 1)
    static let accentInfo = UIColor(red: 92 / 255, green: 108 / 255, blue: 126 / 255, alpha: 1)

    static let borderWidth: CGFloat = 1
    static let sheetShadowOpacity: Float = 0.18
    static let sheetShadowRadius: CGFloat = 28
    static let sheetShadowOffset = CGSize(width: 0, height: -10)
}

enum KuriSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum KuriMetrics {
    static let headerHeight: CGFloat = 62
    static let sheetHorizontalInset: CGFloat = 18
    static let inputHeight: CGFloat = 36
    static let primaryButtonHeight: CGFloat = 56
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 28
    static let chipHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 8
}
