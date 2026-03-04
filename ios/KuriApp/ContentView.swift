import SwiftUI
import KuriCore
import KuriStore

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock
                    ConnectionStatusPanel(model: model)

                    if let bannerMessage = model.bannerMessage {
                        StatusStrip(message: bannerMessage)
                    }

                    if model.recentItems.isEmpty {
                        EmptyCaptureState()
                    } else {
                        captureSection(title: "Recent", items: model.recentItems)
                    }

                    if !model.failedItems.isEmpty {
                        captureSection(title: "Needs Attention", items: model.failedItems)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(KuriSwiftUITheme.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.triggerForegroundSync()
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KURI")
                .font(KuriSwiftUITheme.heroTitle)
                .foregroundStyle(KuriSwiftUITheme.inkPrimary)

            Text("Capture fast. Sort clean. Sync later.")
                .font(KuriSwiftUITheme.bodySmall)
                .foregroundStyle(KuriSwiftUITheme.inkMuted)
        }
        .padding(.top, 12)
    }

    private func captureSection(title: String, items: [CaptureItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: title)

            VStack(spacing: 12) {
                ForEach(items) { item in
                    CaptureCard(item: item)
                }
            }
        }
    }
}

private struct ConnectionStatusPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(KuriSwiftUITheme.inkPrimary)

                    Text(subtitle)
                        .font(KuriSwiftUITheme.bodySmall)
                        .foregroundStyle(KuriSwiftUITheme.inkMuted)
                }

                Spacer(minLength: 0)

                StatusPill(text: connectionBadgeTitle, color: connectionBadgeColor)
            }

            if model.connectionState == .connected {
                VStack(alignment: .leading, spacing: 8) {
                    if let workspaceName = model.workspaceName {
                        metaRow(label: "WORKSPACE", value: workspaceName)
                    }
                    if let databaseID = model.databaseID {
                        metaRow(label: "DATABASE", value: databaseID)
                    }
                    if let lastSyncAt = model.lastSyncAt {
                        metaRow(label: "LAST SYNC", value: lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            Button(actionTitle) {
                Task {
                    await model.connectNotion()
                }
            }
            .buttonStyle(KuriPrimaryButtonStyle())
            .disabled(buttonDisabled)
            .opacity(buttonDisabled ? 0.72 : 1)
        }
        .kuriCard()
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(KuriSwiftUITheme.caption)
                .tracking(1)
                .foregroundStyle(KuriSwiftUITheme.inkMuted)

            Text(value)
                .font(KuriSwiftUITheme.monoCaption)
                .foregroundStyle(KuriSwiftUITheme.inkPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch model.connectionState {
        case .disconnected:
            return "Notion Connection Required"
        case .connecting:
            return "Connecting Workspace"
        case .connected:
            return "Workspace Connected"
        case .actionRequired:
            return "Reconnect Required"
        }
    }

    private var subtitle: String {
        switch model.connectionState {
        case .disconnected:
            return "Link your workspace to start syncing captures to Notion."
        case .connecting:
            return model.isBootstrapping ? "Preparing your workspace and template database." : "Complete the authorization flow in the browser."
        case .connected:
            return "Captures save locally first, then sync into your database in the background."
        case .actionRequired:
            return "Your session expired or setup was interrupted. Connect again to resume sync."
        }
    }

    private var actionTitle: String {
        switch model.connectionState {
        case .connected:
            return "RECONNECT"
        case .connecting:
            return "CONNECTING..."
        case .disconnected, .actionRequired:
            return "CONNECT"
        }
    }

    private var buttonDisabled: Bool {
        model.connectionState == .connecting || model.isBootstrapping
    }

    private var connectionBadgeTitle: String {
        switch model.connectionState {
        case .connected:
            return "ONLINE"
        case .connecting:
            return "SETUP"
        case .disconnected:
            return "OFFLINE"
        case .actionRequired:
            return "ACTION"
        }
    }

    private var connectionBadgeColor: Color {
        switch model.connectionState {
        case .connected:
            return KuriSwiftUITheme.accentSuccess
        case .connecting:
            return KuriSwiftUITheme.accentPending
        case .disconnected:
            return KuriSwiftUITheme.inkMuted
        case .actionRequired:
            return KuriSwiftUITheme.accentWarning
        }
    }
}

private struct StatusStrip: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(KuriSwiftUITheme.accentPending)
                .frame(width: 10, height: 10)

            Text(message)
                .font(KuriSwiftUITheme.bodySmall)
                .foregroundStyle(KuriSwiftUITheme.inkPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(KuriSwiftUITheme.surfaceSecondary)
        .overlay(
            Rectangle()
                .stroke(KuriSwiftUITheme.borderSubtle, lineWidth: 1)
        )
    }
}

private struct EmptyCaptureState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Recent")

            VStack(alignment: .leading, spacing: 12) {
                Text("No captures yet.")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(KuriSwiftUITheme.inkPrimary)

                Text("Save something from X, Threads, Instagram, or Safari to start building your capture log.")
                    .font(KuriSwiftUITheme.bodySmall)
                    .foregroundStyle(KuriSwiftUITheme.inkMuted)
            }
            .kuriCard()
        }
    }
}

private struct CaptureCard: View {
    let item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(KuriSwiftUITheme.inkPrimary)
                        .lineLimit(2)

                    Text(item.sourceApp.notionValue.uppercased())
                        .font(KuriSwiftUITheme.caption)
                        .tracking(1)
                        .foregroundStyle(KuriSwiftUITheme.inkMuted)
                }

                Spacer(minLength: 0)

                StatusPill(text: statusLabel, color: statusColor)
            }

            if !item.tags.isEmpty {
                Text(item.tags.joined(separator: "  ·  ").uppercased())
                    .font(KuriSwiftUITheme.caption)
                    .foregroundStyle(KuriSwiftUITheme.inkPrimary)
            }

            if let memo = item.memo, !memo.isEmpty {
                Text(memo)
                    .font(KuriSwiftUITheme.bodySmall)
                    .foregroundStyle(KuriSwiftUITheme.inkPrimary)
                    .lineLimit(3)
            }

            HStack {
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened).uppercased())
                    .font(KuriSwiftUITheme.monoCaption)
                    .foregroundStyle(KuriSwiftUITheme.inkMuted)

                Spacer(minLength: 0)

                if item.status == .failed, let message = failureMessage(item) {
                    Text(message)
                        .font(KuriSwiftUITheme.caption)
                        .foregroundStyle(KuriSwiftUITheme.accentError)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .kuriCard()
    }

    private var statusLabel: String {
        if item.notionPageID != nil {
            return "SYNCED"
        }
        return item.status.rawValue.uppercased()
    }

    private var statusColor: Color {
        switch item.notionPageID != nil ? SyncStatus.synced : item.status {
        case .pending:
            return KuriSwiftUITheme.accentPending
        case .syncing:
            return KuriSwiftUITheme.accentPending
        case .synced:
            return KuriSwiftUITheme.accentSuccess
        case .failed:
            return KuriSwiftUITheme.accentWarning
        }
    }

    private func failureMessage(_ item: CaptureItem) -> String? {
        let source = [item.lastErrorCode, item.lastErrorMessage]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if source.isEmpty {
            return "SYNC DELAYED"
        }
        if source.contains("401") || source.contains("unauthorized") {
            return "RECONNECT NOTION"
        }
        if source.contains("timeout") || source.contains("timed out") {
            return "RETRYING SOON"
        }
        if source.contains("500") || source.contains("server") {
            return "SERVER DELAY"
        }
        if source.contains("missing_database_id") {
            return "SETUP INCOMPLETE"
        }
        return "RETRYING SOON"
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(KuriSwiftUITheme.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                Capsule()
                    .stroke(color, lineWidth: 1)
            )
    }
}

private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(KuriSwiftUITheme.sectionLabel)
            .tracking(1)
            .foregroundStyle(KuriSwiftUITheme.inkMuted)
    }
}
