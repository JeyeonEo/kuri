# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Unified test runner (PREFERRED — use this in plans)
scripts/run-tests.sh              # Run all: SPM + backend + Xcode build
scripts/run-tests.sh --changed    # Smart mode: only test affected modules
scripts/run-tests.sh --spm        # SPM unit tests only
scripts/run-tests.sh --backend    # Backend tests only
scripts/run-tests.sh --xcode      # Xcode build verification only

# Individual commands (for debugging specific failures)
SWIFTPM_MODULECACHE_OVERRIDE=.build/module-cache swift test
swift test --filter KuriCoreTests
swift test --filter KuriStoreTests
swift test --filter KuriSyncTests
cd backend && npm test
cd ios && xcodegen generate
```

## Test Routine (REQUIRED for all implementation plans)

**Every implementation plan MUST include test verification steps.** When writing plans or executing tasks:

1. **Before starting:** Run `scripts/run-tests.sh` to establish a green baseline
2. **After each logical step:** Run `scripts/run-tests.sh --changed` to catch regressions early
3. **Before completion:** Run `scripts/run-tests.sh` (full suite) to verify nothing is broken

**Module dependency cascade** — the script handles this automatically:
- KuriCore changes → also test KuriStore, KuriSync
- KuriStore changes → also test KuriSync
- backend/ changes → backend tests
- ios/ changes → Xcode build check

**Planning agents:** When creating implementation plans, include `scripts/run-tests.sh --changed` after each step and `scripts/run-tests.sh` as the final verification step. Never mark a plan as complete without a passing full test run.

## Architecture

Kuri is an iOS capture-and-sync app with a share extension. Users capture content (URLs, text, images) via the iOS share sheet, store it locally in SQLite, and sync to a Notion workspace through a Node.js backend.

### Swift Package Modules (Sources/)

Four SPM libraries shared between the main app and share extension:

- **KuriCore** — Domain models (`CaptureItem`, `CaptureDraft`, `SourceApp`, `SyncStatus`, `OCRStatus`), title generation (`TitleBuilder`). All types are `Sendable`.
- **KuriStore** — SQLite persistence using C bindings (`SQLiteCaptureRepository`). Thread-safe writes via serial `DispatchQueue`. Three tables: `capture_items`, `recent_tags`, `app_state`. Conforms to `CaptureRepository` and `AppStateRepository` protocols.
- **KuriSync** — Sync orchestration (`SyncEngine`). Runs OCR before sync, posts `CaptureSyncPayload` to backend, handles retries with exponential backoff (15s → 2m → 15m). Dependencies injected via protocols: `CaptureSyncClient`, `OCRProcessor`, `SyncScheduler`.
- **KuriObservability** — Performance monitoring with `PerformanceMonitor.Span` for timing critical paths.

**Dependency graph:** KuriSync → KuriStore → KuriCore; KuriSync → KuriObservability → KuriCore

### iOS App (ios/)

Built with XcodeGen (`ios/project.yml`). Two targets sharing `SharedUI/`:

- **KuriApp** — Main app with `AppModel` (view model), `ContentView` (SwiftUI), `NotionConnectionClient` (OAuth + workspace bootstrap). Depends on all four SPM modules.
- **KuriShareExtension** — Share sheet UI built in UIKit (`ShareViewController`). Extracts shared content, provides tag selection and memo input, saves via `CaptureRepository`. Does not depend on KuriSync.

Both targets share data through an App Group container (SQLite DB + image files).

### Backend (backend/)

Zero-dependency Node.js server (`server.js`, port 8787). Endpoints: OAuth start/callback, workspace bootstrap, capture sync, telemetry. File-based JSON state in `data/state.json`.

### Data Flow

1. Share Extension extracts content → user adds tags/memo → `CaptureDraft` saved to SQLite → Darwin notification (`com.yona.kuri.newCapture`) posted
2. Images stored in App Group directory; OCR marked pending if image present
3. `SyncEngine.runPendingSync()` fetches pending items → runs OCR if needed → recalculates title → POSTs to backend → marks synced with `notionPageId` → deletes local image file

### Sync Triggers

- **App launch** — initial sync + schedules 15-min BGAppRefreshTaskRequest
- **Foreground return** — `scenePhase` `.active` detection (30s throttle)
- **Share Extension save** — Darwin notification triggers immediate foreground sync
- **Background refresh** — BGTaskScheduler fires every ~15 min, re-schedules after each run
- **Pull-to-refresh** — manual trigger in ContentView
- **Retry schedule** — `AppSyncScheduler.scheduleRetry()` for failed items (15s → 2m → 15m)

## API Guidelines

- **UIKit buttons (iOS 17+ target):** Always use `UIButton.Configuration` API. Never use deprecated properties like `contentEdgeInsets`, `adjustsImageWhenHighlighted`, `imageEdgeInsets`, or `titleEdgeInsets`.
- **SwiftUI background tasks:** The `.backgroundTask` scene modifier only supports `.appRefresh` and `.urlSession` — there is no `.processing` variant. Use `BGAppRefreshTaskRequest` (not `BGProcessingTaskRequest`) when scheduling tasks handled by this modifier.
- **Plan → code:** When implementing from a plan document, verify API names actually exist before using them. Plan docs may contain hallucinated or confused API names.

## Key Conventions

- **Swift 6.1 toolchain, Swift 6.0 language mode** — strict concurrency required, all shared types must be `Sendable`
- **Platforms:** iOS 17.0+, macOS 14.0+
- **Testing framework:** Swift Testing (`@Test` macro syntax, not XCTest)
- **Protocol-driven dependencies** for testability — tests use test doubles (e.g., `TestClient`, `TestOCR`, `TestScheduler`)
- **UIKit for share extension**, SwiftUI for main app
- **Theme system:** `KuriTheme` (UIKit colors/metrics), `KuriSwiftUITheme` (SwiftUI bridge) in `SharedUI/`

## Quick Reference
- **Platform**: iOS 17+ / macOS 14+
- **Language**: Swift 6.0
- **UI Framework**: SwiftUI
- **Architecture**: MVVM with @Observable
- **Minimum Deployment**: iOS 17.0
- **Package Manager**: Swift Package Manager

## XcodeBuildMCP Integration
**IMPORTANT**: This project uses XcodeBuildMCP for all Xcode operations.
- Build: `mcp__xcodebuildmcp__build_sim_name_proj`
- Test: `mcp__xcodebuildmcp__test_sim_name_proj`
- Clean: `mcp__xcodebuildmcp__clean`


## Coding Standards

### Swift Style
- Use Swift 6 strict concurrency
- Prefer `@Observable` over `ObservableObject`
- Use `async/await` for all async operations
- Follow Apple's Swift API Design Guidelines
- Use `guard` for early exits
- Prefer value types (structs) over reference types (classes)

### SwiftUI Patterns
- Extract views when they exceed 100 lines
- Use `@State` for local view state only
- Use `@Environment` for dependency injection
- Prefer `NavigationStack` over deprecated `NavigationView`
- Use `@Bindable` for bindings to @Observable objects

### Navigation Pattern
```swift
// Use NavigationStack with type-safe routing
enum Route: Hashable {
    case detail(Item)
    case settings
}

NavigationStack(path: $router.path) {
    ContentView()
        .navigationDestination(for: Route.self) { route in
            // Handle routing
        }
}