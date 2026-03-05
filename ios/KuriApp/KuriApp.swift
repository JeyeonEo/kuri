import SwiftUI
import KuriStore
import KuriCore
import KuriSync
import KuriObservability

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
