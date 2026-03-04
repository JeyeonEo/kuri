import Foundation
import SwiftUI
import UIKit
import KuriCore
import KuriStore
import KuriSync
import KuriObservability

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var recentItems: [CaptureItem] = []
    @Published private(set) var failedItems: [CaptureItem] = []
    @Published private(set) var connectionState: ConnectionStatus = .disconnected
    @Published private(set) var workspaceName: String?
    @Published private(set) var databaseID: String?
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isBootstrapping = false
    @Published var bannerMessage: String?

    private let repository: SQLiteCaptureRepository
    private let stateRepository: any AppStateRepository
    private let syncEngine: SyncEngine
    private let connectionClient: NotionConnectionClient

    init(
        repository: SQLiteCaptureRepository,
        syncEngine: SyncEngine,
        connectionClient: NotionConnectionClient
    ) {
        self.repository = repository
        self.stateRepository = repository
        self.syncEngine = syncEngine
        self.connectionClient = connectionClient
    }

    static func bootstrap() -> AppModel {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.kuri.shared")!
            .appendingPathComponent("Kuri", isDirectory: true)
        let repository = try! StoreEnvironment.makeRepository(baseDirectory: base)
        let connectionClient = NotionConnectionClient(baseURL: URL(string: "http://localhost:8787")!)
        let client = URLSessionCaptureSyncClient(baseURL: connectionClient.baseURL) { [weak repository] in
            guard let repository else { return nil }
            return try? repository.string(for: .sessionToken)
        }
        let scheduler = AppSyncScheduler()
        let syncEngine = SyncEngine(
            repository: repository,
            client: client,
            ocrProcessor: VisionOCRProcessor(),
            scheduler: scheduler,
            performanceMonitor: PerformanceMonitor(),
            databaseIdProvider: { [weak repository] in
                guard let repository else { return nil }
                return try? repository.string(for: .databaseID)
            }
        )
        return AppModel(repository: repository, syncEngine: syncEngine, connectionClient: connectionClient)
    }

    func loadState() {
        let snapshot = try? stateRepository.snapshot()
        connectionState = snapshot?.connectionStatus ?? .disconnected
        workspaceName = snapshot?.workspaceName
        databaseID = snapshot?.databaseID
        lastSyncAt = snapshot?.lastSyncAt
        reload()
    }

    func reload() {
        recentItems = (try? repository.recentItems(limit: 30)) ?? []
        failedItems = recentItems.filter { $0.status == .failed }
    }

    func connectNotion() async {
        let snapshot = try? stateRepository.snapshot()
        guard let installationID = snapshot?.installationID else {
            applyConnectionState(.actionRequired, banner: "설치 정보를 준비하지 못했어요.", persist: false)
            return
        }

        do {
            try persistConnectionState(.connecting)
            connectionState = .connecting
            bannerMessage = "Notion 연결을 시작하는 중이에요."
            let authorizeURL = try await connectionClient.startOAuth(installationID: installationID)
            await UIApplication.shared.open(authorizeURL)
        } catch {
            handleConnectionFailure(error)
        }
    }

    func handleOAuthCallback(_ url: URL) async {
        do {
            let completion = try await connectionClient.completeOAuth(from: url)
            if completion.status == .actionRequired {
                applyConnectionState(.actionRequired, banner: userFacingCallbackFailure(reason: completion.failureReason))
                return
            }

            try stateRepository.setString(completion.sessionToken, for: .sessionToken)
            if let databaseID = completion.databaseID {
                try stateRepository.setString(databaseID, for: .databaseID)
            }
            if let workspaceName = completion.workspaceName {
                try stateRepository.setString(workspaceName, for: .workspaceName)
            }
            applyConnectionState(.connecting, banner: "Notion 워크스페이스를 준비하는 중이에요.")
            await bootstrapWorkspaceIfNeeded()
        } catch {
            handleConnectionFailure(error)
        }
    }

    func bootstrapWorkspaceIfNeeded() async {
        let snapshot = try? stateRepository.snapshot()
        guard
            let installationID = snapshot?.installationID,
            let sessionToken = snapshot?.sessionToken
        else {
            applyConnectionState(.disconnected, banner: "Notion 연결이 필요해요.", persist: false)
            return
        }

        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            let workspace = try await connectionClient.bootstrapWorkspace(
                sessionToken: sessionToken,
                installationID: installationID
            )
            try stateRepository.setString(workspace.databaseID, for: .databaseID)
            try stateRepository.setString(workspace.workspaceName, for: .workspaceName)
            try persistConnectionState(workspace.status)
            connectionState = workspace.status
            workspaceName = workspace.workspaceName
            databaseID = workspace.databaseID
            bannerMessage = "Notion 연결이 완료됐어요."
        } catch {
            handleConnectionFailure(error)
        }
    }

    func triggerForegroundSync() async {
        loadState()
        let snapshot = try? stateRepository.snapshot()
        guard snapshot?.sessionToken != nil, snapshot?.databaseID != nil else {
            bannerMessage = connectionState == .connected ? "동기화 설정을 다시 확인해 주세요." : "Notion 연결 후 동기화돼요."
            return
        }

        await syncEngine.runPendingSync(limit: 20)
        try? stateRepository.setString(ISO8601DateFormatter().string(from: .now), for: .lastSyncAt)
        lastSyncAt = .now
        reload()
        bannerMessage = failedItems.isEmpty ? "최근 항목이 Notion과 동기화됐어요." : "일부 항목은 잠시 후 다시 동기화돼요."
    }

    func disconnectNotion() {
        try? stateRepository.setString(nil, for: .sessionToken)
        try? stateRepository.setString(nil, for: .databaseID)
        try? stateRepository.setString(nil, for: .workspaceName)
        try? stateRepository.setString(ConnectionStatus.disconnected.rawValue, for: .connectionStatus)
        connectionState = .disconnected
        workspaceName = nil
        databaseID = nil
        bannerMessage = "Notion 연결이 해제됐어요."
    }

    func deleteItem(_ item: CaptureItem) {
        try? repository.delete(id: item.id)
        reload()
    }

    private func userFacingConnectionError(from error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("401") || message.contains("unauthorized") {
            return "Notion을 다시 연결해 주세요."
        }
        if message.contains("timed out") || message.contains("timeout") {
            return "연결이 지연되고 있어요. 잠시 후 다시 시도해 주세요."
        }
        return "연결 중 문제가 생겼어요. 다시 시도해 주세요."
    }

    private func userFacingCallbackFailure(reason: String?) -> String {
        guard let reason else {
            return "Notion 연결을 완료하지 못했어요."
        }
        if reason == "missing_state" {
            return "연결 요청 정보가 없어 다시 시도해 주세요."
        }
        return "Notion 연결을 완료하지 못했어요."
    }

    private func handleConnectionFailure(_ error: Error) {
        applyConnectionState(.actionRequired, banner: userFacingConnectionError(from: error))
    }

    private func applyConnectionState(_ status: ConnectionStatus, banner: String?, persist: Bool = true) {
        if persist {
            try? persistConnectionState(status)
        }
        connectionState = status
        bannerMessage = banner
    }

    private func persistConnectionState(_ status: ConnectionStatus) throws {
        try stateRepository.setString(status.rawValue, for: .connectionStatus)
    }
}

import BackgroundTasks

final class AppSyncScheduler: SyncScheduler {
    static let syncTaskIdentifier = "com.kuri.app.sync"

    func triggerForegroundSync() {
        // Foreground sync is handled directly by AppModel.triggerForegroundSync()
    }

    func scheduleRetry(for itemID: UUID, at date: Date) {
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.earliestBeginDate = date
        request.requiresNetworkConnectivity = true
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Best-effort scheduling; sync will retry on next foreground
        }
    }
}
