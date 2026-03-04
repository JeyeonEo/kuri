# KURI

속도 최우선 iOS MVP 골격이다.

## 구성

- `Package.swift`: 공유 Swift 모듈
- `Sources/KuriCore`: 도메인 모델과 title 생성 규칙
- `Sources/KuriStore`: App Group용 SQLite 저장소
- `Sources/KuriSync`: 비동기 sync 엔진
- `Sources/KuriObservability`: 성능 계측
- `ios/`: XcodeGen 기반 앱/Share Extension 소스
- `backend/`: 외부 의존성 없는 Node 백엔드

## 로컬 실행

### Swift tests

```bash
SWIFTPM_MODULECACHE_OVERRIDE=.build/module-cache swift test
```

### Backend tests

```bash
cd backend
npm test
```

### Xcode 프로젝트 생성

`xcodegen`이 설치되어 있으면:

```bash
cd ios
xcodegen generate
```
