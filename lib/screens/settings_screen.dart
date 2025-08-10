import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../viewmodels/home_viewmodel.dart';
import '../services/background_service.dart';
import 'package:android_intent_plus/android_intent.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정'), centerTitle: true),
      body: Consumer<HomeViewModel>(
        builder: (context, vm, _) {
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('자정 자동 생성'),
                subtitle: const Text('자정 무렵 오늘 일기를 자동으로 생성합니다'),
                value: vm.autoEnabled,
                onChanged: (v) async {
                  await vm.setAutoEnabled(v);
                  if (v) {
                    await BackgroundService.configure(vm);
                  } else {
                    await BackgroundService.stop();
                  }
                },
              ),
              SwitchListTile(
                title: const Text('생성 결과 알림 받기'),
                value: vm.notifyEnabled,
                onChanged: (v) async {
                  await vm.setNotifyEnabled(v);
                },
              ),
              SwitchListTile(
                title: const Text('Wi‑Fi에서만 실행'),
                subtitle: const Text('모바일 데이터 사용을 피합니다'),
                value: vm.wifiOnly,
                onChanged: (v) async {
                  await vm.setWifiOnly(v);
                },
              ),
              ListTile(
                title: const Text('샘플링 간격(분)'),
                subtitle: Text('${vm.samplingMinutes}분'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final ctrl = TextEditingController(text: vm.samplingMinutes.toString());
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('샘플링 간격 설정'),
                      content: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: '분(5 이상)'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final parsed = int.tryParse(ctrl.text.trim()) ?? vm.samplingMinutes;
                    await vm.setSamplingMinutes(parsed);
                  }
                },
              ),
              ListTile(
                title: const Text('자동 생성 시각'),
                subtitle: Text('${vm.runHour.toString().padLeft(2, '0')}:${vm.runMinute.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final hCtrl = TextEditingController(text: vm.runHour.toString());
                  final mCtrl = TextEditingController(text: vm.runMinute.toString());
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('자동 생성 시각 설정'),
                      content: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: hCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: '시(0~23)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: mCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: '분(0~59)'),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final h = int.tryParse(hCtrl.text.trim());
                    final m = int.tryParse(mCtrl.text.trim());
                    if (h != null && h >= 0 && h <= 23 && m != null && m >= 0 && m <= 59) {
                      await vm.setRunTime(hour: h, minute: m);
                    }
                  }
                },
              ),
              ListTile(
                title: const Text('히스토리 최대 보관 개수'),
                subtitle: Text('${vm.historyLimit}개'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final ctrl = TextEditingController(text: vm.historyLimit.toString());
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('히스토리 보관 개수 설정'),
                      content: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: '최소 10개'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final parsed = int.tryParse(ctrl.text.trim()) ?? vm.historyLimit;
                    await vm.setHistoryLimit(parsed);
                  }
                },
              ),
              const Divider(height: 24),
              ListTile(
                title: const Text('권한 설정 열기'),
                subtitle: const Text('위치(항상), 사진, 캘린더 권한을 확인/허용하세요'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  // Open OS app settings
                  // Defer to permission_handler
                  openAppSettings();
                },
              ),
              ListTile(
                title: const Text('지금 위치 샘플 기록'),
                subtitle: const Text('동선 요약 품질을 높일 수 있어요'),
                trailing: const Icon(Icons.my_location_rounded),
                onTap: () async {
                  await context.read<HomeViewModel>().sampleLocationNow();
                },
              ),
              SwitchListTile(
                title: const Text('클라우드 이미지 생성 사용'),
                subtitle: const Text('비활성화 시 로컬 파스텔톤 필터 사용'),
                value: vm.imageCloudEnabled,
                onChanged: (v) async => vm.setImageCloudEnabled(v),
              ),
              ListTile(
                title: const Text('이미지 크기(가로x세로)'),
                subtitle: Text('${vm.imageWidth ?? '-'} x ${vm.imageHeight ?? '-'}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final wCtrl = TextEditingController(text: vm.imageWidth?.toString() ?? '');
                  final hCtrl = TextEditingController(text: vm.imageHeight?.toString() ?? '');
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('이미지 크기 설정'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: wCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '가로(px) 비우면 기본값'),
                          ),
                          TextField(
                            controller: hCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '세로(px) 비우면 기본값'),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final w = int.tryParse(wCtrl.text.trim());
                    final h = int.tryParse(hCtrl.text.trim());
                    await vm.setImageResolution(width: w, height: h);
                  }
                },
              ),
              ListTile(
                title: const Text('이미지 스타일'),
                subtitle: Text(vm.imageStyle ?? '기본'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final ctrl = TextEditingController(text: vm.imageStyle ?? '');
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('이미지 스타일 키워드'),
                      content: TextField(
                        controller: ctrl,
                        decoration: const InputDecoration(hintText: '예: pastel, watercolor, soft light'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await vm.setImageStyle(ctrl.text);
                  }
                },
              ),
              ListTile(
                title: const Text('배터리 최적화 해제 가이드'),
                subtitle: const Text('자동 생성이 중단되지 않도록 설정을 확인하세요'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  // Attempt to open battery optimization settings on Android
                  try {
                    const intent = AndroidIntent(
                      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
                    );
                    await intent.launch();
                  } catch (_) {
                    // fallback: app settings
                    openAppSettings();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}


