# Kuri 개발 현황

최종 업데이트: 2026-03-05

## 모듈별 구현 현황

### KuriCore (완료)

| 기능 | 상태 | 비고 |
|------|------|------|
| `CaptureItem` 도메인 모델 | 완료 | Sendable, sync/OCR 상태 포함 |
| `CaptureDraft` 입력 모델 | 완료 | Share Extension에서 생성 |
| `SourceApp` 자동 감지 | 완료 | Threads, Instagram, X, Safari, Web |
| `TitleBuilder` 제목 생성 | 완료 | 텍스트 → OCR → URL+날짜 우선순위 |
| `CaptureSyncPayload` | 완료 | Backend POST body |
| `AuthUser` 모델 | 완료 | Apple Sign-In 사용자 |

### KuriStore (완료)

| 기능 | 상태 | 비고 |
|------|------|------|
| SQLite CRUD | 완료 | 3개 테이블: capture_items, recent_tags, app_state |
| Sync 상태 전이 | 완료 | pending → syncing → synced/failed |
| OCR 상태 업데이트 | 완료 | 텍스트 저장 + 제목 재계산 |
| 태그 관리 | 완료 | rename (merge-on-collision), delete, merge |
| Auth 사용자 저장 | 완료 | saveAuthUser/loadAuthUser/clearAuthUser |
| Thread-safe 쓰기 | 완료 | Serial DispatchQueue |

### KuriSync (완료)

| 기능 | 상태 | 비고 |
|------|------|------|
| 배치 동기화 | 완료 | 최대 20개씩 처리 |
| OCR → Sync 파이프라인 | 완료 | OCR 완료 후 동기화 |
| 지수 백오프 재시도 | 완료 | 15s → 2m → 15m, 최대 3회 |
| Non-retryable 에러 처리 | 완료 | 재시도 없이 실패 처리 |
| VisionOCR | 완료 | Apple Vision 프레임워크 |

### iOS App (완료)

| 기능 | 상태 | 비고 |
|------|------|------|
| 캡처 목록 (ContentView) | 완료 | SwiftUI, @Observable AppModel |
| Notion 연동 (OAuth) | 완료 | NotionConnectionClient |
| 태그 관리 UI | 완료 | TagManagementView — rename/delete/merge |
| 설정 화면 | 완료 | SettingsView |
| 백그라운드 동기화 | 완료 | BGAppRefreshTaskRequest, 15분 주기, scenePhase 복귀 sync |
| Darwin notification | 완료 | Share Extension → App 즉시 sync (com.yona.kuri.newCapture) |
| 이미지 정리 | 완료 | 동기화 성공 후 로컬 이미지 삭제 |
| Apple Sign-In | 완료 | AuthClient + SignInView |
| 텔레메트리 | 완료 | TelemetryUploader |

### Share Extension (완료)

| 기능 | 상태 | 비고 |
|------|------|------|
| 콘텐츠 추출 | 완료 | URL, 텍스트, 이미지 |
| 태그 입력 + 자동완성 | 완료 | 최근 태그 기반 |
| 메모 입력 | 완료 | |
| UIButton.Configuration | 완료 | deprecated API 제거 완료 |

### Backend (완료)

| 기능 | 상태 | 비고 |
|------|------|------|
| Apple Sign-In 인증 | 완료 | JWT 검증 |
| Notion OAuth | 완료 | CSRF state (10분 TTL) |
| Workspace bootstrap | 완료 | DB 생성/조회, rootPageId 자동 해결 (Search API) |
| 캡처 동기화 | 완료 | 중복 감지 포함 |
| 텔레메트리 수집 | 완료 | |
| Health check | 완료 | |
| Cloudflare Workers 배포 | 완료 | wrangler.toml 설정 완료 |

## 보안 강화 (2026-03-05 완료)

- Force unwrap 제거
- 동기화 타임아웃 15초
- 요청 본문 1MB 제한
- OAuth CSRF state TTL 10분
- 세션 TTL 7일
- 입력 검증 강화 (clientItemId UUID 형식)
- UIButton.Configuration 마이그레이션

## 백그라운드 동기화 완성 (2026-03-05 완료)

- BGTaskScheduler Info.plist 등록 (`com.yona.kuri.app.sync`)
- scenePhase foreground return sync (30초 throttle)
- 15분 주기 background refresh (BGAppRefreshTaskRequest)
- Darwin notification: Share Extension 저장 → App 즉시 sync
- 동기화 성공 후 로컬 이미지 자동 삭제

## 배포 인프라 (2026-03-05 완료)

- Backend: Cloudflare Workers
- iOS: TestFlight 아카이브 스크립트 (`scripts/archive-testflight.sh`)
- XcodeGen 프로젝트 생성

## 개발 계획 문서

| 문서 | 날짜 | 내용 |
|------|------|------|
| `docs/plans/2026-03-04-mvp-completion.md` | 03-04 | MVP 전체 완성 계획 |
| `docs/plans/2026-03-04-manual-testing-design.md` | 03-04 | 수동 테스트 시나리오 |
| `docs/plans/2026-03-04-share-extension-ui-polish.md` | 03-04 | Share Extension UI 개선 |
| `docs/plans/2026-03-05-security-hardening.md` | 03-05 | 보안 강화 9개 항목 |
| `docs/plans/2026-03-05-production-readiness-design.md` | 03-05 | Cloudflare Workers 아키텍처 |
| `docs/plans/2026-03-05-production-readiness-plan.md` | 03-05 | 프로덕션 배포 계획 |
| `docs/plans/2026-03-05-tag-management-design.md` | 03-05 | 태그 관리 설계 |
| `docs/plans/2026-03-05-tag-management-plan.md` | 03-05 | 태그 관리 TDD 계획 |
| `docs/plans/2026-03-05-milestone1-notion-live-mode.md` | 03-05 | Notion Live 모드 검증 계획 |
| `docs/plans/2026-03-05-background-sync-completion-design.md` | 03-05 | 백그라운드 동기화 완성 설계 |
| `docs/plans/2026-03-05-background-sync-completion.md` | 03-05 | 백그라운드 동기화 구현 계획 |
