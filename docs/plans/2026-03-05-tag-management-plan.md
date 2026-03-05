# Tag Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add browse, rename, delete, and merge tag capabilities via a Settings screen.

**Architecture:** Add four methods to `CaptureRepository` protocol, implement in `SQLiteCaptureRepository` with transactional SQL, expose via `AppModel`, and build a `TagManagementView` in SwiftUI accessible from `SettingsView`.

**Tech Stack:** Swift 6.0, SwiftUI, SQLite (C bindings), Swift Testing

---

### Task 1: Add `allTags()` to protocol and implement

**Files:**
- Modify: `Sources/KuriStore/CaptureRepository.swift:7-19` (protocol)
- Modify: `Sources/KuriStore/CaptureRepository.swift:211-233` (near `recentTags`)
- Test: `Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift`

**Step 1: Write the failing test**

```swift
@Test func allTagsReturnsAllTagsSortedByUseCount() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["swift"], imagePayloads: []))
    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "B", memo: "", tags: ["swift", "ios"], imagePayloads: []))
    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "C", memo: "", tags: ["swift", "ios", "ai"], imagePayloads: []))

    let tags = try repository.allTags()
    #expect(tags.count == 3)
    #expect(tags[0].name == "swift")
    #expect(tags[0].useCount == 3)
    #expect(tags[1].name == "ios")
    #expect(tags[1].useCount == 2)
    #expect(tags[2].name == "ai")
    #expect(tags[2].useCount == 1)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SQLiteCaptureRepositoryTests`
Expected: FAIL — `allTags()` not defined

**Step 3: Add `allTags()` to protocol and implement**

Add to `CaptureRepository` protocol (line ~18):
```swift
func allTags() throws -> [RecentTag]
```

Add implementation in `SQLiteCaptureRepository` (after `recentTags` method):
```swift
public func allTags() throws -> [RecentTag] {
    let query = """
    SELECT name, last_used_at, use_count
    FROM recent_tags
    ORDER BY use_count DESC, name ASC
    """
    let stmt = try prepare(query)
    defer { sqlite3_finalize(stmt) }

    var results: [RecentTag] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        results.append(
            RecentTag(
                name: String(cString: sqlite3_column_text(stmt, 0)),
                lastUsedAt: try date(at: 1, stmt: stmt),
                useCount: Int(sqlite3_column_int(stmt, 2))
            )
        )
    }
    return results
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SQLiteCaptureRepositoryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/KuriStore/CaptureRepository.swift Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift
git commit -m "feat(store): add allTags() to CaptureRepository"
```

---

### Task 2: Add `renameTag()` to protocol and implement

**Files:**
- Modify: `Sources/KuriStore/CaptureRepository.swift`
- Test: `Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift`

**Step 1: Write the failing tests**

```swift
@Test func renameTagUpdatesAllCapturesAndRecentTags() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item1 = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["swift", "ios"], imagePayloads: []))
    let item2 = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "B", memo: "", tags: ["swift"], imagePayloads: []))

    try repository.renameTag("swift", to: "swiftlang")

    let updated1 = try repository.item(id: item1.id)
    let updated2 = try repository.item(id: item2.id)
    #expect(updated1?.tags == ["swiftlang", "ios"])
    #expect(updated2?.tags == ["swiftlang"])

    let allTags = try repository.allTags()
    let tagNames = allTags.map(\.name)
    #expect(tagNames.contains("swiftlang"))
    #expect(!tagNames.contains("swift"))
}

@Test func renameTagToExistingNameMerges() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["dev", "development"], imagePayloads: []))

    try repository.renameTag("dev", to: "development")

    let updated = try repository.item(id: item.id)
    #expect(updated?.tags == ["development"])

    let allTags = try repository.allTags()
    #expect(allTags.count == 1)
    #expect(allTags[0].name == "development")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SQLiteCaptureRepositoryTests`
Expected: FAIL — `renameTag` not defined

**Step 3: Add protocol method and implement**

Add to protocol:
```swift
func renameTag(_ oldName: String, to newName: String) throws
```

Implementation:
```swift
public func renameTag(_ oldName: String, to newName: String) throws {
    let normalized = newName.normalizedTag
    guard !normalized.isEmpty else { return }
    let oldNormalized = oldName.normalizedTag
    guard oldNormalized != normalized else { return }

    try writerQueue.sync {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            // Update tags_json in all capture_items containing the old tag
            let selectQuery = "SELECT id, tags_json FROM capture_items WHERE tags_json LIKE ?"
            let selectStmt = try prepare(selectQuery)
            defer { sqlite3_finalize(selectStmt) }
            let pattern = "%\(oldNormalized)%"
            sqlite3_bind_text(selectStmt, 1, pattern, -1, SQLITE_TRANSIENT)

            var updates: [(String, [String])] = []
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(selectStmt, 0))
                let tagsData = Data(
                    bytes: sqlite3_column_blob(selectStmt, 1),
                    count: Int(sqlite3_column_bytes(selectStmt, 1))
                )
                var tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
                let hadOld = tags.contains(oldNormalized)
                let hasNew = tags.contains(normalized)
                if hadOld {
                    tags.removeAll { $0 == oldNormalized }
                    if !hasNew { tags.append(normalized) }
                    updates.append((id, tags))
                }
            }

            let updateQuery = "UPDATE capture_items SET tags_json = ?, updated_at = ? WHERE id = ?"
            for (id, tags) in updates {
                let stmt = try prepare(updateQuery)
                let tagsJSON = try JSONEncoder().encode(tags)
                sqlite3_bind_text(stmt, 1, String(data: tagsJSON, encoding: .utf8), -1, SQLITE_TRANSIENT)
                try bind(date: Date(), to: 2, in: stmt)
                sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    sqlite3_finalize(stmt)
                    throw lastError(updateQuery)
                }
                sqlite3_finalize(stmt)
            }

            // Update recent_tags: merge use counts if target exists
            let existingStmt = try prepare("SELECT use_count FROM recent_tags WHERE name = ?")
            sqlite3_bind_text(existingStmt, 1, normalized, -1, SQLITE_TRANSIENT)
            let targetExists = sqlite3_step(existingStmt) == SQLITE_ROW
            let targetCount = targetExists ? Int(sqlite3_column_int(existingStmt, 0)) : 0
            sqlite3_finalize(existingStmt)

            let oldStmt = try prepare("SELECT use_count FROM recent_tags WHERE name = ?")
            sqlite3_bind_text(oldStmt, 1, oldNormalized, -1, SQLITE_TRANSIENT)
            let oldCount = sqlite3_step(oldStmt) == SQLITE_ROW ? Int(sqlite3_column_int(oldStmt, 0)) : 0
            sqlite3_finalize(oldStmt)

            // Delete old tag
            let deleteStmt = try prepare("DELETE FROM recent_tags WHERE name = ?")
            sqlite3_bind_text(deleteStmt, 1, oldNormalized, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
            sqlite3_finalize(deleteStmt)

            // Insert or update target tag
            let mergedCount = targetCount + oldCount
            let upsertQuery = """
            INSERT INTO recent_tags (name, last_used_at, use_count) VALUES (?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET use_count = ?
            """
            let upsertStmt = try prepare(upsertQuery)
            sqlite3_bind_text(upsertStmt, 1, normalized, -1, SQLITE_TRANSIENT)
            try bind(date: Date(), to: 2, in: upsertStmt)
            sqlite3_bind_int(upsertStmt, 3, Int32(mergedCount))
            sqlite3_bind_int(upsertStmt, 4, Int32(mergedCount))
            guard sqlite3_step(upsertStmt) == SQLITE_DONE else {
                sqlite3_finalize(upsertStmt)
                throw lastError(upsertQuery)
            }
            sqlite3_finalize(upsertStmt)

            try execute("COMMIT TRANSACTION")
        } catch {
            try? execute("ROLLBACK TRANSACTION")
            throw error
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SQLiteCaptureRepositoryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/KuriStore/CaptureRepository.swift Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift
git commit -m "feat(store): add renameTag() with merge support"
```

---

### Task 3: Add `deleteTag()` to protocol and implement

**Files:**
- Modify: `Sources/KuriStore/CaptureRepository.swift`
- Test: `Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift`

**Step 1: Write the failing test**

```swift
@Test func deleteTagRemovesFromAllCapturesAndRecentTags() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    let item = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["swift", "ios"], imagePayloads: []))

    try repository.deleteTag("swift")

    let updated = try repository.item(id: item.id)
    #expect(updated?.tags == ["ios"])

    let allTags = try repository.allTags()
    #expect(!allTags.map(\.name).contains("swift"))
    #expect(allTags.map(\.name).contains("ios"))
}

@Test func deleteNonExistentTagIsNoOp() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["swift"], imagePayloads: []))

    try repository.deleteTag("nonexistent")

    let allTags = try repository.allTags()
    #expect(allTags.count == 1)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SQLiteCaptureRepositoryTests`
Expected: FAIL — `deleteTag` not defined

**Step 3: Add protocol method and implement**

Add to protocol:
```swift
func deleteTag(_ name: String) throws
```

Implementation:
```swift
public func deleteTag(_ name: String) throws {
    let normalized = name.normalizedTag
    guard !normalized.isEmpty else { return }

    try writerQueue.sync {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let selectQuery = "SELECT id, tags_json FROM capture_items WHERE tags_json LIKE ?"
            let selectStmt = try prepare(selectQuery)
            defer { sqlite3_finalize(selectStmt) }
            let pattern = "%\(normalized)%"
            sqlite3_bind_text(selectStmt, 1, pattern, -1, SQLITE_TRANSIENT)

            var updates: [(String, [String])] = []
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(selectStmt, 0))
                let tagsData = Data(
                    bytes: sqlite3_column_blob(selectStmt, 1),
                    count: Int(sqlite3_column_bytes(selectStmt, 1))
                )
                var tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
                if tags.contains(normalized) {
                    tags.removeAll { $0 == normalized }
                    updates.append((id, tags))
                }
            }

            let updateQuery = "UPDATE capture_items SET tags_json = ?, updated_at = ? WHERE id = ?"
            for (id, tags) in updates {
                let stmt = try prepare(updateQuery)
                let tagsJSON = try JSONEncoder().encode(tags)
                sqlite3_bind_text(stmt, 1, String(data: tagsJSON, encoding: .utf8), -1, SQLITE_TRANSIENT)
                try bind(date: Date(), to: 2, in: stmt)
                sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    sqlite3_finalize(stmt)
                    throw lastError(updateQuery)
                }
                sqlite3_finalize(stmt)
            }

            let deleteStmt = try prepare("DELETE FROM recent_tags WHERE name = ?")
            sqlite3_bind_text(deleteStmt, 1, normalized, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
            sqlite3_finalize(deleteStmt)

            try execute("COMMIT TRANSACTION")
        } catch {
            try? execute("ROLLBACK TRANSACTION")
            throw error
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SQLiteCaptureRepositoryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/KuriStore/CaptureRepository.swift Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift
git commit -m "feat(store): add deleteTag() to remove tag from all captures"
```

---

### Task 4: Add `mergeTags()` to protocol and implement

**Files:**
- Modify: `Sources/KuriStore/CaptureRepository.swift`
- Test: `Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift`

**Step 1: Write the failing test**

```swift
@Test func mergeTagsCombinesSourceIntoTarget() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try StoreEnvironment.makeRepository(baseDirectory: root)

    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "A", memo: "", tags: ["dev"], imagePayloads: []))
    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "B", memo: "", tags: ["development"], imagePayloads: []))
    _ = try repository.save(CaptureDraft(sourceApp: .threads, sourceURL: nil, sharedText: "C", memo: "", tags: ["dev", "development"], imagePayloads: []))

    try repository.mergeTags(source: "dev", into: "development")

    let allTags = try repository.allTags()
    #expect(allTags.count == 1)
    #expect(allTags[0].name == "development")
    #expect(allTags[0].useCount == 3)

    let items = try repository.recentItems(limit: 10)
    for item in items {
        #expect(!item.tags.contains("dev"))
        #expect(item.tags.contains("development"))
        #expect(item.tags.filter { $0 == "development" }.count == 1)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SQLiteCaptureRepositoryTests`
Expected: FAIL — `mergeTags` not defined

**Step 3: Add protocol method and implement**

Add to protocol:
```swift
func mergeTags(source: String, into target: String) throws
```

Implementation — `mergeTags` delegates to `renameTag` since rename already handles the merge case (renaming to an existing tag deduplicates):

```swift
public func mergeTags(source: String, into target: String) throws {
    try renameTag(source, to: target)
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SQLiteCaptureRepositoryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/KuriStore/CaptureRepository.swift Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift
git commit -m "feat(store): add mergeTags() using renameTag delegation"
```

---

### Task 5: Expose tag management in AppModel

**Files:**
- Modify: `ios/KuriApp/AppModel.swift`

**Step 1: Add published property and methods**

Add to `AppModel` class:
```swift
@Published private(set) var allTags: [RecentTag] = []

func loadTags() {
    do {
        allTags = try repository.allTags()
    } catch {
        bannerMessage = "태그를 불러올 수 없습니다"
    }
}

func renameTag(_ oldName: String, to newName: String) {
    do {
        try repository.renameTag(oldName, to: newName)
        loadTags()
        reloadItems()
    } catch {
        bannerMessage = "태그 이름을 변경할 수 없습니다"
    }
}

func deleteTag(_ name: String) {
    do {
        try repository.deleteTag(name)
        loadTags()
        reloadItems()
    } catch {
        bannerMessage = "태그를 삭제할 수 없습니다"
    }
}

func mergeTags(sources: [String], into target: String) {
    do {
        for source in sources where source != target {
            try repository.mergeTags(source: source, into: target)
        }
        loadTags()
        reloadItems()
    } catch {
        bannerMessage = "태그를 병합할 수 없습니다"
    }
}
```

**Step 2: Run tests to verify nothing breaks**

Run: `scripts/run-tests.sh --changed`
Expected: PASS

**Step 3: Commit**

```bash
git add ios/KuriApp/AppModel.swift
git commit -m "feat(app): expose tag management methods in AppModel"
```

---

### Task 6: Build TagManagementView

**Files:**
- Create: `ios/KuriApp/TagManagementView.swift`
- Modify: `ios/KuriApp/SettingsView.swift`
- Modify: `ios/project.yml` (add new file to sources if needed by XcodeGen)

**Step 1: Create TagManagementView**

```swift
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
```

**Step 2: Add navigation link in SettingsView**

In `ios/KuriApp/SettingsView.swift`, add a new section before "정보":

```swift
Section("태그") {
    NavigationLink("태그 관리") {
        TagManagementView(model: model)
    }
}
```

**Step 3: Run build verification**

Run: `scripts/run-tests.sh --xcode`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add ios/KuriApp/TagManagementView.swift ios/KuriApp/SettingsView.swift
git commit -m "feat(app): add TagManagementView with rename, delete, merge"
```

---

### Task 7: Full test suite verification

**Step 1: Run full test suite**

Run: `scripts/run-tests.sh`
Expected: All tests pass

**Step 2: Manual verification checklist**

- [ ] Settings → 태그 관리 shows all tags
- [ ] Swipe to delete works with confirmation
- [ ] Tap pencil → rename works
- [ ] Merge mode → select 2+ tags → merge works
- [ ] Empty state shows when no tags exist
- [ ] Sort toggle between usage/alphabetical works
