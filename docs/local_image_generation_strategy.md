# 로컬 이미지 생성 전략

하루결의 사진/이미지 처리는 개인 사진을 외부 서버로 보내지 않는 것을 기본 원칙으로 둔다. 텍스트 일기 생성은 API를 사용할 수 있지만, 이미지 생성/변환은 기기 안에서 처리한다.

## 현재 MVP

- 앱은 선택한 사진을 서버로 업로드하지 않는다.
- `GeminiService.generateIllustrationBytes()`는 로컬 이미지 처리만 수행한다.
- 현재 구현은 실제 diffusion 모델이 아니라, 모바일에서 즉시 동작하는 로컬 파스텔 변환 엔진이다.
- 이 단계의 목적은 개인정보 보호 UX, 히스토리 저장, 다이어리 화면 흐름을 먼저 안정화하는 것이다.

## 목표 구조

### Android

- 1순위: MediaPipe Image Generator
- 모델 계열: Stable Diffusion v1.5 호환 foundation model
- 실행 방식: Android native module에서 MediaPipe Tasks 실행 후 Flutter MethodChannel로 결과 전달
- 조건 이미지 기반 변환이 필요하면 MediaPipe plugin model 또는 경량 ControlNet 계열을 검토

### iOS

- 1순위: Apple Core ML Stable Diffusion
- 모델 계열: Stable Diffusion 2.1 base 또는 Stable Diffusion 1.5 기반 Core ML 변환 모델
- 실행 방식: Swift native module에서 Core ML/Neural Engine 실행 후 Flutter MethodChannel로 결과 전달
- 앱 용량 문제 때문에 모델은 최초 실행 후 Wi-Fi 다운로드 방식이 적합하다.

## 최소 지원 사양 제안

### 권장 최소 사양

- iOS: iPhone 12 / A14 이상, iOS 17 이상 권장
- Android: RAM 8GB 이상, Snapdragon 888급 이상 권장
- 저장 공간: 모델 다운로드용 여유 공간 3GB 이상 권장
- 생성 해상도: MVP는 512x512부터 시작
- 생성 step: 12~20 step 범위에서 품질/속도 조절

### 실제 제품 정책

- 기본값: 로컬 파스텔 변환
- 고성능 기기: 온디바이스 diffusion 옵션 활성화
- 저사양 기기: diffusion 옵션 숨김 또는 비활성화
- 배터리 20% 이하, 고온 상태, 절전 모드에서는 diffusion 생성 제한

## 모델 선택 기준

1. 앱 크기와 다운로드 부담이 작아야 한다.
2. 512x512 생성이 30초 안쪽으로 끝나는 기기를 1차 목표로 둔다.
3. 원본 사진을 완전히 새 이미지로 대체하기보다, 다이어리용 스타일 이미지 생성에 집중한다.
4. LoRA는 후순위다. 먼저 foundation model을 안정화하고, 이후 `pastel diary` 스타일 LoRA를 붙인다.

## 구현 단계

1. Flutter MVP 완성
   - 사진 선택
   - 일정/기분/메모 입력
   - 일기 생성
   - 로컬 파스텔 변환
   - 히스토리 저장

2. Android 로컬 diffusion PoC
   - MediaPipe Image Generator 샘플 프로젝트 확인
   - SD 1.5 호환 모델 변환
   - MethodChannel 연결
   - 512x512, 12 step 기준 벤치마크

3. iOS 로컬 diffusion PoC
   - Apple Core ML Stable Diffusion Swift package 확인
   - Core ML 변환 모델 준비
   - MethodChannel 연결
   - Neural Engine 사용 벤치마크

4. 기기별 옵션화
   - 최초 실행 시 기기 RAM/OS/칩셋 확인
   - 모델 다운로드 가능 여부 안내
   - 저사양 기기는 로컬 파스텔 변환만 제공

## 참고 링크

- Google AI Edge MediaPipe Image Generator: https://ai.google.dev/edge/mediapipe/solutions/vision/image_generator
- Android guide: https://ai.google.dev/edge/mediapipe/solutions/vision/image_generator/android
- Apple Core ML Stable Diffusion: https://github.com/apple/ml-stable-diffusion
- Qualcomm AI Hub Stable Diffusion v1.5 mobile listing: https://aihub.qualcomm.com/mobile/models/stable_diffusion_v1_5
