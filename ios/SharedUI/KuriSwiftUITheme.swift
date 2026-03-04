import SwiftUI
import UIKit

enum KuriSwiftUITheme {
    static let surfacePrimary = Color(uiColor: KuriTheme.surfacePrimary)
    static let surfaceSecondary = Color(uiColor: KuriTheme.surfaceSecondary)
    static let appBackground = Color(uiColor: KuriTheme.appBackground)
    static let inkPrimary = Color(uiColor: KuriTheme.inkPrimary)
    static let inkMuted = Color(uiColor: KuriTheme.inkMuted)
    static let borderSubtle = Color(uiColor: KuriTheme.borderSubtle)
    static let accentSuccess = Color(uiColor: KuriTheme.accentSuccess)
    static let accentPending = Color(uiColor: KuriTheme.accentPending)
    static let accentWarning = Color(uiColor: KuriTheme.accentWarning)
    static let accentError = Color(uiColor: KuriTheme.accentError)

    static let heroTitle = Font.system(size: 28, weight: .bold)
    static let sectionLabel = Font.system(size: 11, weight: .bold)
    static let body = Font.system(size: 16, weight: .medium)
    static let bodySmall = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12, weight: .medium)
    static let monoCaption = Font.system(.caption, design: .monospaced).weight(.medium)
}

struct KuriCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(KuriSwiftUITheme.surfacePrimary)
            .overlay(
                Rectangle()
                    .stroke(KuriSwiftUITheme.borderSubtle, lineWidth: 1)
            )
    }
}

struct KuriPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(KuriSwiftUITheme.surfacePrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(configuration.isPressed ? KuriSwiftUITheme.inkPrimary.opacity(0.9) : KuriSwiftUITheme.inkPrimary)
            .overlay(
                Rectangle()
                    .stroke(KuriSwiftUITheme.inkPrimary, lineWidth: 1)
            )
    }
}

extension View {
    func kuriCard() -> some View {
        modifier(KuriCardModifier())
    }
}
