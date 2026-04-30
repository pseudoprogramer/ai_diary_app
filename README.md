# 하루결

하루결은 사용자가 이미 쓰는 Apple/Google/Galaxy 캘린더와 사진첩의 시간·장소 정보를 바탕으로 하루의 맥락을 복원하고, 감성 일기와 대표 기억 장면을 만들어주는 Flutter 기반 iOS/Android 앱입니다.

핵심 원칙은 새 캘린더 습관을 강요하지 않고, 개인 사진을 외부 이미지 생성 서버로 보내지 않는 것입니다. 현재 MVP는 사진을 기기 안에서 파스텔 다이어리 이미지로 변환하며, 이후 Android는 MediaPipe Image Generator, iOS는 Core ML Stable Diffusion 기반 온디바이스 이미지 생성을 붙이는 방향으로 확장합니다.

## 빠른 시작

필수: Flutter, Android Studio, iOS 빌드는 macOS + Xcode 필요

```bash
git clone https://github.com/pseudoprogramer/ai_diary_app.git
cd ai_diary_app
flutter pub get
flutter run
```

## 환경 변수

루트에 `.env` 파일을 만들 수 있습니다. 이미지 생성용 API 키는 사용하지 않습니다.

```env
GEMINI_API_KEY=
```

`GEMINI_API_KEY`가 없으면 일기 텍스트도 로컬 fallback 문장으로 생성됩니다.

## 핵심 에이전트 흐름

1. 사용자는 기존 캘린더 앱에 일정을 그대로 작성합니다.
2. 하루결은 사용자가 허용한 캘린더의 일정 정보를 읽습니다.
3. 하루결은 사진첩에서 오늘 촬영한 사진의 시간/장소 정보를 읽습니다.
4. 일정 시간대와 사진의 시간/장소를 비교해 오늘의 활동을 추론합니다.
5. 사용자는 타임라인에서 포함/제외, 라벨, 한 줄 메모만 가볍게 조정합니다.
6. 하루가 끝나면 감성 일기와 대표 기억 장면을 생성합니다.

## 현재 MVP 기능

- 기분/문체 선택
- 오늘 일정과 한 줄 메모 입력
- 사진 여러 장 선택
- 일정, 메모, 사진 수, 위치/캘린더 힌트를 바탕으로 감성 일기 생성
- 선택한 사진을 로컬 파스텔 다이어리 이미지로 변환
- 히스토리 저장/삭제
- 이미지 저장/공유
- 자동 생성 시간, 알림, 위치 샘플링 설정

## 다음 MVP 목표

- 캘린더 목록 가져오기
- 포함할 캘린더 선택 저장
- 오늘 일정 가져오기
- 오늘 사진 가져오기
- 시간 기준 일정-사진 매칭
- 오늘의 흐름 타임라인 표시

자세한 내용은 `docs/context_matching_agent.md`를 참고하세요.

## 로컬 이미지 생성 정책

- 원본 사진은 이미지 생성 서버로 전송하지 않습니다.
- 현재 버전은 `image` 패키지를 이용한 로컬 파스텔 변환을 사용합니다.
- 실제 온디바이스 diffusion은 네이티브 모듈로 분리해 붙입니다.
- Android 후보: MediaPipe Image Generator + Stable Diffusion v1.5 호환 모델
- iOS 후보: Apple Core ML Stable Diffusion

자세한 내용은 `docs/local_image_generation_strategy.md`를 참고하세요.

## 플랫폼 메모

### Android

```bash
flutter pub get
flutter run
```

권한: 사진, 위치, 캘린더, 알림. 자동 생성 안정성을 위해 배터리 최적화 예외 설정이 필요할 수 있습니다.

### iOS

macOS + Xcode 필요.

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run
```

권한: 사진, 위치, 캘린더, 알림. iOS 백그라운드 실행은 OS 정책상 정확한 시간 실행을 보장하지 않습니다.
