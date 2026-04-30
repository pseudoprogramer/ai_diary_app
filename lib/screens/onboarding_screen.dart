import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingScreen extends StatelessWidget {
  final VoidCallback onFinish;
  const OnboardingScreen({super.key, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text('AI 그림일기 시작하기', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text('자동으로 오늘의 순간을 모아 일기를 만들어드려요. 다음 권한이 필요합니다:'),
              const SizedBox(height: 16),
              const _Bullet('위치(항상): 동선 요약 및 자동 실행'),
              const _Bullet('사진: 오늘의 사진 탐색 및 저장'),
              const _Bullet('캘린더: 주요 일정 요약'),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await Permission.locationAlways.request();
                  await Permission.photos.request();
                  await Permission.notification.request();
                  await Permission.calendarFullAccess.request();
                  onFinish();
                },
                child: const Text('권한 허용하고 시작하기'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onFinish,
                child: const Text('나중에 설정'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(height: 1.5)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}


