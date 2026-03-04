# KURI MVP PRD

## 1. 제품 개요

### 제품명 (가칭)

KURI

일본어로 다람쥐라는 뜻. 다람쥐가 알밤을 숨겨두듯이 내 지식들을 차곡차곡 잘 저장해두기.

### 한 줄 정의

소셜에서 발견한 인사이트를 공유 한 번으로 개인 Notion 데이터베이스에 구조화해 저장하는 앱.

## 2. 문제 정의

### 핵심 문제

좋은 콘텐츠는 많이 소비하지만, 개인 자산(지식 시스템)으로 축적되지 않는다.

### 구체적 문제

- SNS 저장은 앱 안에 갇힘
- Notion 직접 저장은 모바일에서 번거로움
- 링크만 저장하면 맥락이 사라짐
- 플랫폼 정책상 본문이 공유되지 않는 경우 존재

## 3. MVP 목표

### 제품 목표

- 공유 -> 저장 성공률 99% 체감
- 첫 저장까지 60초 이내
- Notion 연결 이탈 최소화

### 사용자 목표

- "이건 나중에 써야지" -> 3초 안에 저장
- 태그로 분류되어 나중에 찾을 수 있음

## 4. 타겟 사용자

1. Notion을 사용하는 지식노동자 (PM/마케터/기획자)
2. 콘텐츠 소재를 수집하는 크리에이터
3. 공부 자료를 정리하는 학습형 사용자

공통점: 이미 Notion을 사용하며, 소셜에서 인사이트를 자주 발견함.

## 5. 핵심 사용자 플로우

### 기본 저장 플로우

1. Threads/Instagram/X에서 공유 버튼 클릭
2. 앱 선택
3. 저장 팝업 표시
4. 태그 입력 또는 최근 태그 버튼 선택
5. 1줄 메모 입력 (선택)
6. 저장 완료
7. Notion DB에 구조화된 페이지 생성

### OCR Fallback 플로우

1. 링크로 본문이 안 들어오는 경우
2. 사용자가 스크린샷 촬영
3. 이미지 공유 -> 앱
4. On-device OCR 실행
5. 추출 텍스트를 `Text` 필드에 저장

OCR은 보조 전략이며, 기본 전략은 공유 링크 기반이다.

## 6. MVP 기능 범위

### 필수 포함

- iOS Share Sheet 기반 저장
- URL + 공유 텍스트 수집
- 플랫폼 자동 인식
- 태그 입력 (최근 태그 버튼 포함)
- 1줄 메모 필드
- Notion OAuth 연결
- 템플릿 DB 자동 생성 (기본값)
- Outbox (오프라인/실패 대비 큐)
- 자동 재시도 (최대 3회)
- 저장 성공/실패 상태 표시
- 이미지 첨부 + On-device OCR (Vision Framework)

### MVP 제외

- LLM 요약
- 자동 태깅
- 고급 검색
- 팀 공유 기능

## 7. 데이터 구조 (Notion 템플릿 DB)

필수 속성:

- `Name` (title)
- `URL` (url)
- `Platform` (select)
- `Tags` (multi-select)
- `Memo` (rich text)
- `Text` (rich text)
- `Status` (select: Synced / Pending / Failed)

## 8. 기술 아키텍처 (MVP)

### 클라이언트 (iOS)

- Share Extension
- Vision Framework (OCR, on-device)
- 로컬 Outbox 저장 (CoreData/SQLite)

### 서버 (필수 최소)

- Notion OAuth 처리
- Notion API Proxy (선택)
- 저장 실패 로깅

OCR은 서버 없이 처리한다.

## 9. 리스크 대응 설계

| 리스크 | MVP 대응 |
| --- | --- |
| 플랫폼 본문 제한 | Memo + OCR fallback |
| Notion 설정 복잡 | 템플릿 DB 자동 생성 |
| 저장 실패 | 로컬 Outbox + 재시도 |
| 차별 부족 | 태그 중심 UX + Notion 템플릿 뷰 |

## 10. 성공 지표 (MVP)

- 첫 저장 완료율 >= 70%
- 저장 성공률(체감) >= 99%
- 태그 입력률 >= 50%
- 7일 리텐션 >= 25%
- 재방문율(저장 3회 이상) >= 40%

## 11. 출시 기준 (Launch Checklist)

- Notion 연결 성공률 테스트
- 플랫폼별 공유 테스트 (Threads / Instagram / X / Safari)
- OCR 정확도 테스트 (한글/영문/이모지)
- 오프라인 -> 재연결 시 동기화 정상 작동
- App Store 정책 검토 (스크래핑 표현 금지)
