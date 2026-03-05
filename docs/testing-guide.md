# Kuri 테스트 가이드

## 테스트 실행

```bash
# 전체 테스트 (권장)
scripts/run-tests.sh

# 변경된 모듈만 테스트 (개발 중 사용)
scripts/run-tests.sh --changed

# 개별 실행
scripts/run-tests.sh --spm       # Swift 단위 테스트
scripts/run-tests.sh --backend   # Backend 테스트
scripts/run-tests.sh --xcode     # Xcode 빌드 검증
```

## 테스트 커버리지 현황

### KuriCore — 8개 테스트

`Tests/KuriCoreTests/TitleBuilderTests.swift`

| 테스트 | 검증 내용 |
|--------|----------|
| TitleBuilder.makeTitle | sharedText 우선, OCR 폴백, URL+날짜 폴백 |
| SourceApp.detect | URL 기반 감지 (threads/instagram/x/web), 텍스트 폴백 |
| CaptureSyncPayload | 텍스트 결합, nil 처리, 플랫폼 매핑, 태그/메모 |

### KuriStore — 16개 테스트

`Tests/KuriStoreTests/SQLiteCaptureRepositoryTests.swift`

| 테스트 | 검증 내용 |
|--------|----------|
| savePersistsPendingCaptureAndTags | 태그 정규화, pending 상태 |
| imageDraftStartsWithOCRPending | 이미지 → OCR pending |
| appStateSnapshotCreatesInstallationID | 자동 ID 생성, 라운드트립 |
| pendingItemsExcludesAlreadySyncingEntries | syncing 제외 |
| markSyncedUpdatesStatusAndNotionPageID | synced 전이 |
| markFailedRecordsErrorAndRetryDate | 실패 기록 + 재시도 날짜 |
| updateOCRSetsTextAndNewTitle | OCR 텍스트 + 제목 재계산 |
| clearConnectionStateRemovesSessionAndConnectionInfo | 연결 해제 |
| recentTagsIncrementUseCount | 태그 사용 횟수 |
| pendingItemsExcludesFutureRetryItems | 미래 재시도 제외 |
| saveAndLoadAuthUserRoundTrips | 인증 사용자 저장/로드 |
| allTagsReturnsAllTagsSortedByUseCount | 태그 정렬 |
| deleteItemRemovesCaptureAndImage | 삭제 + 이미지 정리 |
| renameTagUpdatesAllCapturesAndRecentTags | 이름 변경 + 충돌 시 병합 |
| deleteTagRemovesFromAllCapturesAndRecentTags | 태그 삭제 |
| mergeTagsCombinesSourceIntoTarget | 태그 병합, 중복 제거 |

### KuriSync — 8개 테스트 (+1 macOS 전용)

`Tests/KuriSyncTests/SyncEngineTests.swift`

| 테스트 | 검증 내용 |
|--------|----------|
| OCR before sync | pending OCR → OCR 실행 후 동기화 |
| Missing database ID | 비-재시도 실패 |
| Server error | 재시도 스케줄링 |
| Non-retryable error | 재시도 안 함 |
| OCR failure | 재시도 가능 실패 |
| Max retry | 4회 이후 중단 |
| Image cleanup after sync | 성공 후 로컬 이미지 파일 삭제 확인 |
| VisionOCRProcessor | 프로토콜 적합성 (macOS only) |

테스트 더블: `TestClient`, `FailingTestClient`, `TestOCR`, `FailingTestOCR`, `TestScheduler`

### KuriObservability — 1개 테스트

`Tests/KuriObservabilityTests/PerformanceMonitorTests.swift` — smoke test.

### Backend — 통합 테스트

`backend/server.test.js` — Node.js 내장 test runner. 전체 엔드포인트 통합 테스트.

```bash
cd backend && npm test
```

## 테스트 작성 규칙

- **프레임워크:** Swift Testing (`@Test` 매크로, XCTest 아님)
- **패턴:** Protocol-driven 의존성 주입 → 테스트 더블 사용
- **방법론:** TDD (RED → GREEN → REFACTOR)
- **커버리지 목표:** 80% 이상

## 모듈 의존성 캐스케이드

`scripts/run-tests.sh --changed`가 자동 처리:

- KuriCore 변경 → KuriStore, KuriSync도 테스트
- KuriStore 변경 → KuriSync도 테스트
- backend/ 변경 → backend 테스트
- ios/ 변경 → Xcode 빌드 체크
