# AI Diary (Flutter)

자동으로 오늘의 사진/동선/일정을 모아 감성적인 일기 텍스트와 파스텔톤 일러스트를 생성·저장하는 앱입니다. 사용자가 아무것도 하지 않아도 자정(또는 설정한 시각)에 자동으로 실행됩니다.

## 1) 빠른 시작

필수: Flutter, Android Studio(Xcode), 실제 기기 권장

1. 저장소 클론
   ```bash
   git clone https://github.com/pseudoprogramer/ai_diary_app.git
   cd ai_diary_app
   flutter pub get
   ```
2. 환경 변수 파일 준비(.env)
   - 루트에 `.env` 생성(파일 자체는 필요). 민감 값은 비워둔 채 커밋되어 있음
   ```env
   GEMINI_API_KEY=
   IMAGE_API_URL=
   IMAGE_API_KEY=
   ```
3. 앱 실행(안드로이드 에뮬레이터/실기기)
   ```bash
   flutter run
   ```

## 2) iOS(실기기, iPhone 15 Pro Max 등)

macOS + Xcode 필요

1. 의존성 설치
   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```
2. Xcode 서명/설정
   - `ios/Runner.xcworkspace` 열기
   - Runner > Signing & Capabilities: Team 선택, Bundle ID 고유값 지정
   - Background Modes 켜고 “Background fetch” 체크
3. 권한 안내(이미 Info.plist 포함)
   - 위치(WhenInUse/Always), 사진 접근, 캘린더, 알림 사용 설명 문구 포함
4. 실행
   - iPhone 연결 후 `flutter run -d <device>`
   - 첫 실행 시 온보딩에서 위치 항상/사진/캘린더/알림 권한 허용
5. 테스트
   - 홈 AppBar 메뉴 → “자정 파이프라인 테스트 실행”으로 즉시 검증
   - 자동 실행: 설정 → 자동 생성 켜기, 시:분을 현재+1~5분으로 지정 → 백그라운드 대기 → 알림 및 히스토리 확인

## 3) Android(실기기/에뮬레이터)

1. 의존성 설치
   ```bash
   flutter pub get
   ```
2. 권한(이미 AndroidManifest.xml 포함)
   - INTERNET, 위치, 백그라운드 위치, 캘린더, 알림(13+) 등 선언
3. 실행
   ```bash
   flutter run
   ```
4. 테스트
   - 즉시: 홈 → “자정 파이프라인 테스트 실행”
   - 자동: 설정 → 자동 생성 켜기, 시:분 지정 → 백그라운드 대기 → 알림/히스토리 확인
5. 권장
   - 설정 화면의 “배터리 최적화 해제 가이드”로 OS 최적화 예외 처리(제조사별)

## 4) 기능 요약

- 자동 파이프라인(시:분): 오늘 사진 중 의미 있는 사진 여러 장 자동 선별 → 텍스트/일러스트 생성 → 저장/알림
- 일기 텍스트: Gemini(REST). 키 미설정 시 안내 후 폴백
- 일러스트: 클라우드 이미지 API(옵션) → 실패/미사용 시 로컬 파스텔톤 필터
- 히스토리: 목록/상세/삭제/전체삭제, 공유·복사·갤러리 저장
- 설정: 자동 on/off, 실행 시각(시:분), Wi‑Fi 전용, 샘플링 간격, 알림 on/off, 이미지 옵션(클라우드/크기/스타일), 권한/배터리 가이드, 보관 개수

## 5) 환경 변수(.env)

```env
GEMINI_API_KEY=  # Google AI Studio API Key
IMAGE_API_URL=   # (선택) 이미지 생성 REST 엔드포인트
IMAGE_API_KEY=   # (선택) 이미지 생성 API 키
```

## 6) 트러블슈팅

- 오늘 찍은 사진이 없는 경우: 자동 생성 항목 없음
- 백그라운드 실행 시각: 모바일 OS 특성상 정확한 분 보장 X(가까운 시각에 트리거)
- 권한 거부 시: 설정 화면 → 권한 설정 열기 사용
- Android: 알림 권한(13+), 배터리 최적화 해제 권장
- iOS: 백그라운드 App 새로고침 켜기, 저전력 모드 해제 추천

## 7) 라이선스

본 저장소의 코드는 개인/사내 테스트 목적 샘플로 제공됩니다.