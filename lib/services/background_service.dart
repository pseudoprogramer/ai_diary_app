import 'dart:async';

import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/widgets.dart';

import '../viewmodels/home_viewmodel.dart';
import 'daily_pipeline.dart';
import 'location_service.dart';
import 'photo_service.dart';
import 'location_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'notification_service.dart';

class BackgroundService {
  static const String taskId = 'ai_diary_daily_task';

  static Future<void> configure(HomeViewModel vm) async {
    // Register headless task (Android)
    BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);

    await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: 15, // OS decides; we'll gate by local clock
        stopOnTerminate: false,
        enableHeadless: true,
        startOnBoot: true,
        requiredNetworkType: NetworkType.ANY,
      ),
      (String taskId) async {
        await _maybeRunDaily(vm);
        BackgroundFetch.finish(taskId);
      },
      (String taskId) async {
        BackgroundFetch.finish(taskId);
      },
    );

    try {
      await BackgroundFetch.scheduleTask(TaskConfig(
        taskId: taskId,
        delay: 60 * 1000,
        periodic: true,
        stopOnTerminate: false,
        enableHeadless: true,
        requiredNetworkType: NetworkType.ANY,
      ));
    } catch (_) {
      // iOS can reject custom BGProcessing registration on some signing/device
      // states. The default fetch configured above is enough to keep the app
      // usable, so do not crash on launch.
    }
  }

  static Future<void> stop() async {
    try {
      await BackgroundFetch.stop();
    } catch (_) {}
  }

  // Top-level headless task (Android-only). Avoid capturing BuildContext.
  // Instantiate a fresh ViewModel to run the pipeline and persist results.
  @pragma('vm:entry-point')
  static void backgroundFetchHeadlessTask(HeadlessTask task) async {
    WidgetsFlutterBinding.ensureInitialized();
    final String taskId = task.taskId;
    try {
      final vm = HomeViewModel();
      await _maybeRunDaily(vm);
    } finally {
      BackgroundFetch.finish(taskId);
    }
  }

  static DateTime? _lastRun;
  static const String _lastRunKey = 'background_last_run_iso';
  static const String _lastSampleKey = 'last_sample_iso';

  static Future<void> _maybeRunDaily(HomeViewModel vm) async {
    final now = DateTime.now();
    // Allow a small minute window to improve reliability of iOS Background Fetch timing
    final bool inMinuteWindow = (now.minute - vm.runMinute).abs() <= 5;
    final isMidnightWindow = now.hour == vm.runHour && inMinuteWindow;
    if (!vm.autoEnabled) return; // run only when auto is enabled
    final alreadyRan = await _isAlreadyRanToday(now);
    if (!isMidnightWindow || alreadyRan) {
      // Not midnight: log a coarse location sample for route summary
      try {
        // Respect Wi-Fi only option
        if (vm.wifiOnly) {
          final conn = await Connectivity().checkConnectivity();
          final wifi = conn.contains(ConnectivityResult.wifi);
          if (!wifi) return;
        }
        // Respect sampling interval
        final prefs = await SharedPreferences.getInstance();
        final iso = prefs.getString(_lastSampleKey);
        if (iso != null) {
          final last = DateTime.tryParse(iso);
          if (last != null) {
            final diffMin = DateTime.now().difference(last).inMinutes;
            if (diffMin < vm.samplingMinutes) {
              return;
            }
          }
        }
        final pos = await const LocationService().getCoarsePosition();
        if (pos != null) {
          final log = LocationLogService();
          await log.appendSample(LocationSample(
            latitude: pos.latitude,
            longitude: pos.longitude,
            timestamp: DateTime.now(),
          ));
          await prefs.setString(_lastSampleKey, DateTime.now().toIso8601String());
        }
      } catch (_) {}
      return;
    }

    _lastRun = now;
    await _persistLastRun(now);
    // Midnight run: respect Wi-Fi only option
    if (vm.wifiOnly) {
      final conn = await Connectivity().checkConnectivity();
      final wifi = conn.contains(ConnectivityResult.wifi);
      if (!wifi) return;
    }

    final pipeline = DailyPipeline(
      locationService: const LocationService(),
      photoService: const PhotoService(),
      viewModel: vm,
    );
    await pipeline.runOnce();

    // Build route summary and attach to latest entry if available
    final log = LocationLogService();
    final summary = await log.buildRouteSummary(DateTime.now());
    if (summary != null && vm.history.isNotEmpty) {
      // Prepend summary to text of latest item in-memory (persisting edits is skipped for simplicity)
      final latest = vm.history.first;
      vm.setDiaryText('$summary\n\n${latest.text}');
    }

    // Notify user if enabled
    if (vm.notifyEnabled && vm.history.isNotEmpty) {
      await NotificationService.showDailyResult(
        title: '오늘의 AI 그림일기 생성됨',
        body: vm.history.first.text,
      );
    }
  }

  static Future<bool> _isAlreadyRanToday(DateTime now) async {
    if (_lastRun != null && _sameDay(_lastRun!, now)) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final iso = prefs.getString(_lastRunKey);
      if (iso == null) return false;
      final last = DateTime.tryParse(iso);
      if (last == null) return false;
      _lastRun = last;
      return _sameDay(last, now);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _persistLastRun(DateTime dt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRunKey, dt.toIso8601String());
    } catch (_) {}
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

