# AI Diary - Flutter 앱

## 프로젝트 개요
사용자가 아무것도 하지 않아도, 앱이 알아서 하루를 요약하고 아름다운 콘텐츠까지 만들어주는 '마법 같은 경험'을 제공하는 iOS 앱입니다.

## 주요 기능
- 📸 사진 및 메타데이터 자동 수집
- 📍 위치 정보 기반 활동 추적
- 💪 HealthKit 연동 (운동 기록)
- 📅 캘린더 일정 연동
- 🎨 AI 이미지 생성 (DALL-E, Midjourney 등)
- ✍️ AI 감성 글귀 작성
- 🔒 iOS 개인정보보호 정책 완전 준수

## 개발 환경 설정

### 1. Flutter 설치
1. [Flutter 공식 사이트](https://flutter.dev/docs/get-started/install/windows)에서 Flutter SDK 다운로드
2. 압축 해제 후 원하는 경로에 설치 (예: `C:\flutter`)
3. 환경 변수 PATH에 Flutter bin 폴더 추가
4. 터미널에서 `flutter doctor` 실행하여 설치 확인

### 2. iOS 개발 환경 (macOS 필요)
- Xcode 설치
- iOS Simulator 설정
- Apple Developer 계정 (실제 기기 테스트용)

### 3. Android 개발 환경
- Android Studio 설치
- Android SDK 설정
- Android 에뮬레이터 설정

## 프로젝트 구조
```
ai_diary/
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── day_summary.dart
│   │   ├── activity_event.dart
│   │   └── ai_content.dart
│   ├── services/
│   │   ├── data_collector.dart
│   │   ├── ai_service.dart
│   │   └── permission_handler.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── permission_screen.dart
│   │   └── diary_screen.dart
│   └── widgets/
│       ├── day_summary_card.dart
│       └── ai_generated_content.dart
├── pubspec.yaml
└── README.md
```

## 개발 단계별 계획

### Phase 1: 기본 구조 및 권한 설정
- [ ] Flutter 프로젝트 생성
- [ ] 기본 UI 구조 설계
- [ ] iOS 권한 요청 구현 (사진, 위치, 건강, 캘린더)

### Phase 2: 데이터 수집 서비스
- [ ] 사진 메타데이터 수집
- [ ] 위치 정보 수집
- [ ] HealthKit 연동
- [ ] 캘린더 데이터 수집

### Phase 3: AI 서비스 연동
- [ ] OpenAI API 연동
- [ ] 이미지 생성 서비스 연동
- [ ] 텍스트 생성 서비스 연동

### Phase 4: UI/UX 구현
- [ ] 메인 화면 디자인
- [ ] 다이어리 카드 UI
- [ ] AI 생성 콘텐츠 표시

### Phase 5: 테스트 및 최적화
- [ ] 단위 테스트
- [ ] 통합 테스트
- [ ] 성능 최적화

## 필요한 주요 패키지
```yaml
dependencies:
  flutter:
    sdk: flutter
  # 권한 관리
  permission_handler: ^10.0.0
  # 위치 서비스
  geolocator: ^9.0.0
  # 사진 접근
  image_picker: ^0.8.0
  # HealthKit (iOS)
  health: ^7.0.0
  # 캘린더
  device_calendar: ^4.0.0
  # HTTP 요청
  http: ^0.13.0
  # 상태 관리
  provider: ^6.0.0
  # 로컬 저장소
  shared_preferences: ^2.0.0
```

## 시작하기
1. Flutter 설치 후 프로젝트 폴더에서:
```bash
flutter pub get
flutter run
```

## 주의사항
- iOS 앱스토어 배포를 위해서는 Apple Developer 계정이 필요합니다
- 모든 데이터 수집은 사용자의 명시적 동의 하에 이루어져야 합니다
- 개인정보보호 정책을 준수하여 개발해야 합니다 

## Progress (2025-08-09)
- Skeleton UI 추가: `lib/screens/home_screen.dart` (이미지 플레이스홀더, 일기 텍스트, 액션 버튼)
- 상태관리 도입: `provider` (`lib/viewmodels/home_viewmodel.dart`)
- 위치 권한 요청 및 현재 위치 조회: `lib/services/location_service.dart` (앱 시작 시 자동 호출)
- Gemini 서비스 스텁 추가: `lib/services/gemini_service.dart`
- `main.dart`에 `MultiProvider`와 dotenv 로딩(미존재 시에도 실행 안전) 구성
- 플랫폼 폴더 생성 및 권한 반영
  - Android: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (`android/app/src/main/AndroidManifest.xml`)
  - iOS: `NSLocationWhenInUseUsageDescription` (`ios/Runner/Info.plist`)
- 자산 폴더 및 `.env` 스캐폴딩, 정적 분석 경고/에러 0건

## Next Steps
- Android 설정 마무리: `flutter doctor --android-licenses` 실행 및 cmdline-tools 설치 확인 (`flutter doctor -v` 참고)
- 자동 일기 생성 로직 구현
  - 최근 사진/EXIF(시간/위치) 수집 → 위치 체류 구간과 결합하여 의미 있는 순간 추출
  - Gemini 프롬프트 설계: 하루 요약 + 파스텔 톤 일러스트 요청
  - `GeminiService`에 실제 HTTP 연동 구현
- 선택 사항: 백그라운드 동선 수집(배터리 고려), 프라이버시 설정 UI