# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Swift package tests (all modules)
SWIFTPM_MODULECACHE_OVERRIDE=.build/module-cache swift test

# Run a single test target
swift test --filter KuriCoreTests
swift test --filter KuriStoreTests
swift test --filter KuriSyncTests

# Backend tests
cd backend && npm test

# Generate Xcode project (requires xcodegen)
cd ios && xcodegen generate
```

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

1. Share Extension extracts content → user adds tags/memo → `CaptureDraft` saved to SQLite
2. Images stored in App Group directory; OCR marked pending if image present
3. `SyncEngine.runPendingSync()` fetches pending items → runs OCR if needed → recalculates title → POSTs to backend → marks synced with `notionPageId`

## Key Conventions

- **Swift 6.1 toolchain, Swift 6.0 language mode** — strict concurrency required, all shared types must be `Sendable`
- **Platforms:** iOS 17.0+, macOS 14.0+
- **Testing framework:** Swift Testing (`@Test` macro syntax, not XCTest)
- **Protocol-driven dependencies** for testability — tests use test doubles (e.g., `TestClient`, `TestOCR`, `TestScheduler`)
- **UIKit for share extension**, SwiftUI for main app
- **Theme system:** `KuriTheme` (UIKit colors/metrics), `KuriSwiftUITheme` (SwiftUI bridge) in `SharedUI/`
