# Testing

## 자동화 테스트

### Swift 패키지 테스트 (전체)

```bash
swift test
```

### 모듈별 실행

```bash
swift test --filter KuriCoreTests
swift test --filter KuriStoreTests
swift test --filter KuriSyncTests
swift test --filter KuriObservabilityTests
```

### 백엔드 테스트

```bash
cd backend && npm test
```

### 테스트 목록

| 모듈 | 테스트 |
|------|--------|
| KuriCore | TitleBuilder — OCR 우선순위, 공유 텍스트 사용, URL+날짜 폴백 |
| KuriStore | 저장/로드, 동기화 상태 전환, OCR 업데이트, 이미지 삭제, App State |
| KuriSync | OCR 후 동기화, 재시도 스케줄링, 재시도 불가 오류 처리 |
| KuriObservability | PerformanceMonitor 스팬 타이밍 |
| Backend | OAuth 흐름, 워크스페이스 부트스트랩, 캡처 동기화, 중복 처리, 텔레메트리 |

---

## 실기기 수동 테스트 (실제 Notion 연동)

### 사전 준비 (최초 1회)

**1. Notion integration 생성**

1. https://www.notion.so/my-integrations 접속
2. **Create new integration** 클릭
3. 이름: "KURI Dev", 타입: **Public integration**
   - Public integration = OAuth 플로우 지원. 마켓플레이스에 게시하지 않으면 본인만 사용 가능.
4. Capabilities: Read content, Update content, Insert content 활성화
5. Distribution → Redirect URIs에 추가:
   `http://<MAC_IP>:8787/v1/oauth/notion/callback`
6. OAuth client ID, OAuth client secret 복사

**2. Xcode 서명 설정**

1. `cd ios && xcodegen generate && open Kuri.xcodeproj`
2. **KuriApp** 타겟 → Signing & Capabilities → Team 선택
3. **KuriShareExtension** 타겟도 동일하게

### 테스트 세션 시작

```bash
# 1. 설정 스크립트 실행 (IP 감지, .env 생성, AppModel.swift 패치, xcodegen)
./scripts/device-test-setup.sh

# 2. 백엔드 실행
cd backend && npm start

# 3. Xcode에서 iPhone 선택 후 Cmd+R
```

### 테스트 시나리오

| # | 시나리오 | 절차 | 확인 포인트 |
|---|---------|------|------------|
| A | Notion 연결 | 앱 실행 → "Notion 연결" 탭 → 브라우저에서 승인 | 워크스페이스 이름 표시 |
| B | 공유 익스텐션 캡처 | Safari/Threads에서 공유 → Kuri 선택 → 태그/메모 입력 → 저장 | 앱에 항목 표시 |
| C | Notion 동기화 | 앱에서 동기화 탭 | Notion 데이터베이스에 페이지 생성 확인 |
| D | 이미지 + OCR | 스크린샷 공유 → 앱 열기 (OCR 처리) → 동기화 | Notion 페이지 Text 필드에 OCR 텍스트 |
| E | 오프라인 → 온라인 | Wi-Fi 끄고 캡처 → Wi-Fi 켜고 동기화 | 상태: pending → synced |
| F | 실패 & 재시도 | 백엔드 중단 → 동기화 시도 → 백엔드 재시작 → 재시도 | 최종 동기화 성공 |
| G | 연결 해제 | 설정 → Notion 연결 해제 → 동기화 시도 | 재연결 안내 메시지 |

### 테스트 세션 종료

```bash
# AppModel.swift를 localhost로 복구
./scripts/device-test-teardown.sh
```

### 트러블슈팅

| 문제 | 해결 |
|------|------|
| IP 감지 실패 | Wi-Fi 연결 확인. `ipconfig getifaddr en0` 직접 실행 |
| 기기에서 백엔드 접근 불가 | Mac과 iPhone이 같은 Wi-Fi인지 확인. 시스템 설정 → 방화벽 → 포트 8787 허용 |
| OAuth 콜백 앱으로 미복귀 | Notion integration의 Redirect URI와 `backend/.env`의 `NOTION_REDIRECT_URI` 일치 여부 확인 |
| 공유 익스텐션 미표시 | Xcode에서 양쪽 타겟 모두 빌드. App Group entitlements 확인 |
| OCR 미동작 | Vision framework는 실기기 필요 (시뮬레이터 불가) |
