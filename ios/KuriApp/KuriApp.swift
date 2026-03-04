import SwiftUI
import KuriStore
import KuriCore
import KuriSync
import KuriObservability

@main
struct KuriApp: App {
    @StateObject private var model = AppModel.bootstrap()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
                    model.loadState()
                    await model.bootstrapWorkspaceIfNeeded()
                    await model.triggerForegroundSync()
                }
                .onOpenURL { url in
                    Task {
                        await model.handleOAuthCallback(url)
                    }
                }
        }
        .backgroundTask(.processing(AppSyncScheduler.syncTaskIdentifier)) {
            await model.triggerForegroundSync()
        }
    }
}
