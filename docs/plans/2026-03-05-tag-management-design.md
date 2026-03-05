# Tag Management Design

**Date:** 2026-03-05
**Status:** Approved

## Overview

Add full tag management to Kuri: browse, rename, delete, and merge tags via a dedicated Settings screen. Tags are currently created during capture but cannot be managed afterward.

## Current State

- Tags stored as `[String]` JSON arrays in `capture_items.tags_json`
- `recent_tags` table tracks name, use_count, last_used_at
- Tags normalized to lowercase with collapsed whitespace
- Share extension: tag input + recent tag suggestions
- Main app: read-only tag display, no management

## Approach

Repository-level CRUD operations + SwiftUI settings screen (Approach 1). Clean separation of data and UI, extensible for future inline access.

## Data Layer

New `CaptureRepository` protocol methods:

```swift
func renameTag(_ oldName: String, to newName: String) throws
func deleteTag(_ name: String) throws
func mergeTags(source: String, into target: String) throws
func allTags() throws -> [RecentTag]
```

### Implementation (SQLiteCaptureRepository)

- **renameTag**: Scan `capture_items` with old tag in `tags_json`, replace with new (normalized), update `recent_tags.name`. Single transaction.
- **deleteTag**: Remove tag from all `capture_items.tags_json` arrays, `DELETE FROM recent_tags`. Single transaction.
- **mergeTags**: Rename source to target, deduplicate any captures with duplicate target tag, merge `use_count`. Single transaction.
- **allTags**: Query `recent_tags ORDER BY use_count DESC` (or alphabetical).

All operations are idempotent and transactional.

## UI Design

### Navigation

Settings → "Manage Tags" → `TagManagementView`

### TagManagementView

- Header with tag count badge
- Sort toggle: by usage count (default) or alphabetical
- Tag list rows: name + usage count
  - Swipe left → Delete (confirmation alert)
  - Tap → Edit sheet (rename field + save)
- Toolbar "Merge" button → selection mode → pick 2+ tags → choose target name → confirm

### Merge Flow

1. Tap "Merge" in toolbar
2. Select 2+ tags via checkmarks
3. Tap "Merge" button
4. Choose which name to keep (or type new)
5. Confirm → merge executed

### Empty State

"No tags yet. Tags you add when capturing will appear here."

## Error Handling

- Rename to existing name → auto-merge with confirmation
- Empty tag name → validation prevents save
- DB failures → transaction rollback + alert
- All operations idempotent

## Sync Impact

- Tag changes are local until next sync
- Existing `SyncEngine` sends updated `tags` arrays — no backend changes needed
- No new API endpoints required

## Testing

- Unit tests for renameTag, deleteTag, mergeTags, allTags
- Edge cases: rename to existing, delete non-existent, merge with self
- UI manual verification for settings screen
