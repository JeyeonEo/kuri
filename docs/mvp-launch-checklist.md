# Kuri MVP 출시 체크리스트

최종 업데이트: 2026-03-05

## 요약

코드 구현은 완료. 남은 작업은 **배포 환경 설정**, **Live 연동 검증**, **TestFlight 배포** 3가지 트랙.

---

## Milestone 1: Notion Live 모드 검증

Notion stub 모드(가짜 응답)에서 실제 Notion API 연동으로 전환.

- [ ] Cloudflare Workers에 시크릿 등록
  - `NOTION_CLIENT_ID`
  - `NOTION_CLIENT_SECRET`
  - `NOTION_REDIRECT_URI`
- [ ] `NOTION_MODE=live` 환경변수 설정
- [x] `rootPageId` 처리 로직 검증 — Search API로 해결, 테스트 추가 완료
- [ ] Notion OAuth 플로우 E2E 확인 (start → callback → token 저장)
- [ ] Workspace bootstrap 확인 (DB 생성/조회)
- [ ] 캡처 동기화 → 실제 Notion 페이지 생성 확인

## Milestone 2: Cloudflare Workers 배포

Backend를 프로덕션 환경에 배포.

- [ ] `wrangler.toml` 프로덕션 설정 확인 (route, zone 등)
- [ ] `wrangler deploy`로 Workers 배포
- [ ] Health check 엔드포인트 응답 확인 (`GET /v1/health`)
- [ ] 커스텀 도메인 연결 (필요 시)
- [ ] 프로덕션 URL을 iOS 앱에 반영 (`AppModel`의 backend URL)

## Milestone 3: Xcode 서명 & TestFlight 배포

iOS 앱을 TestFlight에 올려서 실제 디바이스 테스트.

- [ ] Apple Developer 계정 준비
- [ ] App ID, Bundle ID 등록
- [ ] Signing certificate 생성 (Distribution)
- [ ] Provisioning profile 생성 (App + Share Extension + App Group)
- [ ] `xcodegen generate`로 프로젝트 생성
- [ ] `scripts/archive-testflight.sh`로 아카이브 & 업로드
- [ ] TestFlight 내부 테스터 추가

## Milestone 4: 실 환경 E2E 검증

TestFlight 빌드 + 프로덕션 Backend로 전체 플로우 검증.

- [ ] Apple Sign-In → 세션 생성
- [ ] Notion OAuth 연동
- [ ] Share Extension으로 URL 캡처 → 태그/메모 입력 → 저장
- [ ] Share Extension으로 이미지 캡처 → OCR 처리 확인
- [ ] 앱 진입 → 동기화 트리거 → Notion 페이지 생성 확인
- [ ] 백그라운드 동기화 동작 확인
- [ ] 태그 관리 (rename, delete, merge) 동작 확인
- [ ] 오프라인 → 온라인 복귀 시 동기화 확인

---

## 참고

- 코드 구현 현황: [`docs/development-status.md`](./development-status.md)
- API 레퍼런스: [`docs/api-reference.md`](./api-reference.md)
- 테스트 가이드: [`docs/testing-guide.md`](./testing-guide.md)
