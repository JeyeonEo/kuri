import SwiftUI
import KuriStore
import KuriCore
import KuriSync
import KuriObservability

@MainActor
final class DarwinNotificationObserver {
    static let shared = DarwinNotificationObserver()
    var onNewCapture: (() -> Void)?

    func startObserving() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let obj = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    obj.onNewCapture?()
                }
            },
            "com.yona.kuri.newCapture" as CFString,
            nil,
            .deliverImmediately
        )
    }

    func stopObserving() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(self).toOpaque(), CFNotificationName("com.yona.kuri.newCapture" as CFString), nil)
    }
}

@main
struct KuriApp: App {
    @StateObject private var model = AppModel.bootstrap()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
                    model.loadState()
                    await model.bootstrapWorkspaceIfNeeded()
                    await model.triggerForegroundSync()
                    AppSyncScheduler().scheduleNextRefresh()
                    DarwinNotificationObserver.shared.onNewCapture = {
                        Task {
                            await model.triggerForegroundSync()
                        }
                    }
                    DarwinNotificationObserver.shared.startObserving()
                }
                .onOpenURL { url in
                    Task {
                        await model.handleOAuthCallback(url)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            await model.triggerForegroundSync()
                        }
                    }
                }
        }
        .backgroundTask(.appRefresh(AppSyncScheduler.syncTaskIdentifier)) {
            await model.triggerForegroundSync()
            AppSyncScheduler().scheduleNextRefresh()
        }
    }
}
