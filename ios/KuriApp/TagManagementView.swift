import SwiftUI
import KuriCore

struct TagManagementView: View {
    @ObservedObject var model: AppModel
    @State private var sortByUsage = true
    @State private var editingTag: RecentTag?
    @State private var renameText = ""
    @State private var tagToDelete: RecentTag?
    @State private var isMerging = false
    @State private var selectedForMerge: Set<String> = []
    @State private var mergeTargetName = ""
    @State private var showMergeTargetAlert = false

    private var sortedTags: [RecentTag] {
        if sortByUsage {
            return model.allTags
        } else {
            return model.allTags.sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        List {
            if model.allTags.isEmpty {
                Section {
                    Text("아직 태그가 없습니다. 캡처할 때 추가한 태그가 여기에 표시됩니다.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Picker("정렬", selection: $sortByUsage) {
                        Text("사용순").tag(true)
                        Text("이름순").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section("\(model.allTags.count)개의 태그") {
                    ForEach(sortedTags, id: \.name) { tag in
                        tagRow(tag)
                    }
                    .onDelete { indexSet in
                        let tags = sortedTags
                        for index in indexSet {
                            tagToDelete = tags[index]
                        }
                    }
                }
            }
        }
        .navigationTitle("태그 관리")
        .toolbar {
            if !model.allTags.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isMerging ? "완료" : "병합") {
                        if isMerging {
                            if selectedForMerge.count >= 2 {
                                showMergeTargetAlert = true
                            } else {
                                isMerging = false
                                selectedForMerge.removeAll()
                            }
                        } else {
                            isMerging = true
                        }
                    }
                }
            }
        }
        .onAppear { model.loadTags() }
        .alert("태그 이름 변경", isPresented: .init(
            get: { editingTag != nil },
            set: { if !$0 { editingTag = nil } }
        )) {
            TextField("새 이름", text: $renameText)
            Button("저장") {
                if let tag = editingTag {
                    model.renameTag(tag.name, to: renameText)
                }
                editingTag = nil
            }
            Button("취소", role: .cancel) { editingTag = nil }
        }
        .alert("태그 삭제", isPresented: .init(
            get: { tagToDelete != nil },
            set: { if !$0 { tagToDelete = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let tag = tagToDelete {
                    model.deleteTag(tag.name)
                }
                tagToDelete = nil
            }
            Button("취소", role: .cancel) { tagToDelete = nil }
        } message: {
            if let tag = tagToDelete {
                Text("'\(tag.name)' 태그를 모든 캡처에서 삭제합니다.")
            }
        }
        .alert("병합할 이름 선택", isPresented: $showMergeTargetAlert) {
            TextField("태그 이름", text: $mergeTargetName)
            Button("병합") {
                let sources = Array(selectedForMerge)
                model.mergeTags(sources: sources, into: mergeTargetName)
                isMerging = false
                selectedForMerge.removeAll()
                mergeTargetName = ""
            }
            Button("취소", role: .cancel) {
                showMergeTargetAlert = false
            }
        } message: {
            Text("선택한 \(selectedForMerge.count)개의 태그를 하나로 병합합니다.")
        }
    }

    private func tagRow(_ tag: RecentTag) -> some View {
        HStack {
            if isMerging {
                Image(systemName: selectedForMerge.contains(tag.name) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedForMerge.contains(tag.name) ? .blue : .secondary)
                    .onTapGesture {
                        if selectedForMerge.contains(tag.name) {
                            selectedForMerge.remove(tag.name)
                        } else {
                            selectedForMerge.insert(tag.name)
                            if mergeTargetName.isEmpty {
                                mergeTargetName = tag.name
                            }
                        }
                    }
            }

            VStack(alignment: .leading) {
                Text(tag.name.uppercased())
                    .font(.subheadline.monospaced())
                Text("\(tag.useCount)회 사용")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isMerging {
                Button {
                    renameText = tag.name
                    editingTag = tag
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }
}
