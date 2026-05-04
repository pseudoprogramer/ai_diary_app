import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../services/background_service.dart';
import '../viewmodels/home_viewmodel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정'), centerTitle: true),
      body: Consumer<HomeViewModel>(
        builder: (context, vm, _) {
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              SwitchListTile(
                title: const Text('매일 자동 생성'),
                subtitle: const Text('설정한 시간 무렵 오늘의 일기를 자동으로 생성합니다.'),
                value: vm.autoEnabled,
                onChanged: (value) async {
                  await vm.setAutoEnabled(value);
                  if (value) {
                    await BackgroundService.configure(vm);
                  } else {
                    await BackgroundService.stop();
                  }
                },
              ),
              ListTile(
                title: const Text('자동 생성 시각'),
                subtitle: Text(
                    '${vm.runHour.toString().padLeft(2, '0')}:${vm.runMinute.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editRunTime(context, vm),
              ),
              SwitchListTile(
                title: const Text('생성 결과 알림 받기'),
                value: vm.notifyEnabled,
                onChanged: vm.setNotifyEnabled,
              ),
              SwitchListTile(
                title: const Text('Wi-Fi에서만 자동 실행'),
                subtitle: const Text('모바일 데이터 사용을 줄입니다.'),
                value: vm.wifiOnly,
                onChanged: vm.setWifiOnly,
              ),
              ListTile(
                title: const Text('위치 샘플링 간격'),
                subtitle: Text('${vm.samplingMinutes}분'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editSamplingMinutes(context, vm),
              ),
              const Divider(height: 24),
              const ListTile(
                title: Text('이미지 생성 방식'),
                subtitle:
                    Text('기본은 기기 안에서 빠르게 만들고, 고품질 모드는 Gemini 이미지 생성을 사용합니다.'),
                leading: Icon(Icons.memory_rounded),
              ),
              SwitchListTile(
                title: const Text('고품질 AI 이미지 생성'),
                subtitle: const Text(
                    '켜면 Gemini로 사진과 일기 내용을 보내 그림을 생성합니다. 실패하면 로컬 생성으로 대체됩니다.'),
                value: vm.imageCloudEnabled,
                onChanged: vm.setImageCloudEnabled,
              ),
              ListTile(
                title: const Text('로컬 이미지 스타일'),
                subtitle: Text(vm.imageStyle ?? 'pastel watercolor diary'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editImageStyle(context, vm),
              ),
              ListTile(
                title: const Text('히스토리 최대 보관 개수'),
                subtitle: Text('${vm.historyLimit}개'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editHistoryLimit(context, vm),
              ),
              const Divider(height: 24),
              const ListTile(
                title: Text('권한 설정 열기'),
                subtitle: Text('위치, 사진, 캘린더 권한을 확인합니다.'),
                trailing: Icon(Icons.open_in_new),
                onTap: openAppSettings,
              ),
              ListTile(
                title: const Text('지금 위치 샘플 기록'),
                subtitle: const Text('동선 요약 품질을 높일 수 있습니다.'),
                trailing: const Icon(Icons.my_location_rounded),
                onTap: vm.sampleLocationNow,
              ),
              ListTile(
                title: const Text('배터리 최적화 해제 가이드'),
                subtitle: const Text('자동 생성이 중단되지 않도록 OS 설정을 확인합니다.'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  try {
                    const intent = AndroidIntent(
                      action:
                          'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
                    );
                    await intent.launch();
                  } catch (_) {
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

  Future<void> _editRunTime(BuildContext context, HomeViewModel vm) async {
    final hCtrl = TextEditingController(text: vm.runHour.toString());
    final mCtrl = TextEditingController(text: vm.runMinute.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('자동 생성 시각'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: hCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '시'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: mCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '분'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장')),
        ],
      ),
    );
    if (ok == true) {
      final hour = int.tryParse(hCtrl.text.trim());
      final minute = int.tryParse(mCtrl.text.trim());
      if (hour != null && minute != null) {
        await vm.setRunTime(hour: hour, minute: minute);
      }
    }
  }

  Future<void> _editSamplingMinutes(
      BuildContext context, HomeViewModel vm) async {
    final ctrl = TextEditingController(text: vm.samplingMinutes.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('위치 샘플링 간격'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '분 단위, 최소 5'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장')),
        ],
      ),
    );
    if (ok == true) {
      await vm.setSamplingMinutes(
          int.tryParse(ctrl.text.trim()) ?? vm.samplingMinutes);
    }
  }

  Future<void> _editImageStyle(BuildContext context, HomeViewModel vm) async {
    final ctrl =
        TextEditingController(text: vm.imageStyle ?? 'pastel watercolor diary');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로컬 이미지 스타일'),
        content: TextField(
          controller: ctrl,
          decoration:
              const InputDecoration(hintText: '예: pastel watercolor diary'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장')),
        ],
      ),
    );
    if (ok == true) {
      await vm.setImageStyle(ctrl.text);
    }
  }

  Future<void> _editHistoryLimit(BuildContext context, HomeViewModel vm) async {
    final ctrl = TextEditingController(text: vm.historyLimit.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('히스토리 보관 개수'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '최소 10개'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장')),
        ],
      ),
    );
    if (ok == true) {
      await vm
          .setHistoryLimit(int.tryParse(ctrl.text.trim()) ?? vm.historyLimit);
    }
  }
}
