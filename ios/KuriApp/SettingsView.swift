import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showDisconnectConfirmation = false

    var body: some View {
        List {
            Section("Notion") {
                if let workspace = model.workspaceName {
                    HStack {
                        Text("워크스페이스")
                        Spacer()
                        Text(workspace)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.connectionState == .connected {
                    Button("Notion 연결 해제", role: .destructive) {
                        showDisconnectConfirmation = true
                    }
                }
            }

            Section("정보") {
                HStack {
                    Text("버전")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("설정")
        .confirmationDialog("Notion 연결을 해제할까요?", isPresented: $showDisconnectConfirmation, titleVisibility: .visible) {
            Button("연결 해제", role: .destructive) {
                model.disconnectNotion()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장된 항목은 유지되지만, 새로운 동기화는 중단돼요.")
        }
    }
}
