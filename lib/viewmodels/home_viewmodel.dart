import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/gemini_service.dart';
import '../services/location_service.dart';
import '../models/diary_entry.dart';
import '../services/location_log_service.dart';
import '../services/daily_pipeline.dart';
import '../services/photo_service.dart';
import '../services/calendar_service.dart';

class HomeViewModel extends ChangeNotifier {
  bool _isLoading = false;
  String? _diaryText;
  Uint8List? _generatedImageBytes;
  Uint8List? _originalImageBytes;
  DateTime? _lastPhotoTakenAt;
  bool _showOriginal = false;
  final ImagePicker _imagePicker = ImagePicker();
  final GeminiService _geminiService = GeminiService();
  final LocationService _locationService = const LocationService();
  
  PositionData? _lastPosition;
  PositionData? get lastPosition => _lastPosition;
  String? _placeLabel;
  String? get placeLabel => _placeLabel;
  List<DiaryEntry> _history = const [];
  List<DiaryEntry> get history => _history;
  static const String _historyPrefsKey = 'diary_history';
  static const String _autoEnabledKey = 'auto_enabled';
  static const String _wifiOnlyKey = 'wifi_only';
  static const String _samplingMinutesKey = 'sampling_minutes';
  static const String _notifyEnabledKey = 'notify_enabled';
  static const String _historyLimitKey = 'history_limit';
  static const String _runHourKey = 'run_hour';
  static const String _runMinuteKey = 'run_minute';
  static const String _imgCloudKey = 'img_cloud_enabled';
  static const String _imgWidthKey = 'img_width';
  static const String _imgHeightKey = 'img_height';
  static const String _imgStyleKey = 'img_style';

  bool get isLoading => _isLoading;
  String? get diaryText => _diaryText;
  Uint8List? get generatedImageBytes => _generatedImageBytes;
  Uint8List? get originalImageBytes => _originalImageBytes;
  bool get showOriginal => _showOriginal;
  String? _lastError;
  String? get lastError => _lastError;
  bool _autoEnabled = false;
  bool get autoEnabled => _autoEnabled;
  bool _wifiOnly = false;
  bool get wifiOnly => _wifiOnly;
  int _samplingMinutes = 30;
  int get samplingMinutes => _samplingMinutes;
  bool _notifyEnabled = true;
  bool get notifyEnabled => _notifyEnabled;
  int _historyLimit = 100;
  int get historyLimit => _historyLimit;
  DateTime? _lastSampleAt;
  DateTime? get lastSampleAt => _lastSampleAt;
  int _runHour = 0; // 0 = 자정
  int get runHour => _runHour;
  int _runMinute = 0;
  int get runMinute => _runMinute;
  bool _imageCloudEnabled = true;
  bool get imageCloudEnabled => _imageCloudEnabled;
  int? _imageWidth;
  int? get imageWidth => _imageWidth;
  int? _imageHeight;
  int? get imageHeight => _imageHeight;
  String? _imageStyle;
  String? get imageStyle => _imageStyle;

  void setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  void setDiaryText(String? text) {
    _diaryText = text;
    notifyListeners();
  }

  void setGeneratedImage(Uint8List? bytes) {
    _generatedImageBytes = bytes;
    notifyListeners();
  }

  void setShowOriginal(bool value) {
    if (_showOriginal == value) return;
    _showOriginal = value;
    notifyListeners();
  }

  void toggleShowOriginal() => setShowOriginal(!_showOriginal);

  // Called by background pipeline to update current context
  void updatePositionFromPipeline({required double lat, required double lon, String? placeLabel}) {
    _lastPosition = PositionData(latitude: lat, longitude: lon);
    _placeLabel = placeLabel ?? _placeLabel;
    notifyListeners();
  }

  void _setError(String? message) {
    _lastError = message;
    notifyListeners();
  }

  void consumeError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> requestLocationAndFetch() async {
    final pos = await _locationService.getCurrentPosition();
    if (pos != null) {
      _lastPosition = PositionData(latitude: pos.latitude, longitude: pos.longitude);
      _placeLabel = await _locationService.reverseGeocode(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      notifyListeners();
    }
    await loadHistory();
    await _loadSettings();
  }

  Future<void> createAiDiary() async {
    if (_isLoading) return;
    setLoading(true);
    try {
      if (_geminiService.apiKey.isEmpty) {
        _setError('GEMINI_API_KEY가 설정되지 않았습니다 (.env 확인). 텍스트 생성 없이 진행합니다.');
      }
      final XFile? selected = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (selected == null) {
        return;
      }

      final Uint8List selectedBytes = await selected.readAsBytes();
      _originalImageBytes = selectedBytes;
      setGeneratedImage(selectedBytes);

      final DateTime photoTakenAt = await _readPhotoTakenAt(selected) ?? DateTime.now();
      _lastPhotoTakenAt = photoTakenAt;
      String? locationHint;
      if (_lastPosition != null) {
        locationHint = _placeLabel ??
            '위도 ${_lastPosition!.latitude.toStringAsFixed(4)}, 경도 ${_lastPosition!.longitude.toStringAsFixed(4)}';
      }

      final eventSummary = await CalendarService().buildTodaySummary();
      final String text = await _geminiService.generateDiaryText(
        photoTakenAt: photoTakenAt,
        locationHint: locationHint,
        routeSummary: await _buildRouteSummaryForToday(),
        eventSummary: eventSummary,
      );
      setDiaryText(text);

      final Uint8List imageBytes = await _geminiService.generateIllustrationBytes(
        diaryText: text,
        fallbackImageBytes: _originalImageBytes ?? selectedBytes,
        enableCloud: _imageCloudEnabled,
        width: _imageWidth,
        height: _imageHeight,
        style: _imageStyle,
      );
      setGeneratedImage(imageBytes);

      final saved = await _persistEntry(
        text: text,
        imageBytes: imageBytes,
        photoTakenAt: photoTakenAt,
      );
      if (!saved) {
        _setError('히스토리에 저장하지 못했습니다.');
      }
    } catch (_) {
      // 간단히 무시(추후 에러 상태 관리 추가 가능)
      _setError('작업 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
    } finally {
      setLoading(false);
    }
  }

  // Auto mode: bytes already selected by pipeline
  Future<void> generateFromAuto(Uint8List selectedBytes, DateTime takenAt) async {
    if (_isLoading) return;
    setLoading(true);
    try {
      if (_geminiService.apiKey.isEmpty) {
        _setError('GEMINI_API_KEY가 설정되지 않았습니다 (.env 확인). 텍스트 생성 없이 진행합니다.');
      }
      _originalImageBytes = selectedBytes;
      _lastPhotoTakenAt = takenAt;
      setGeneratedImage(selectedBytes);

      String? locationHint;
      if (_lastPosition != null) {
        locationHint = _placeLabel ??
            '위도 ${_lastPosition!.latitude.toStringAsFixed(4)}, 경도 ${_lastPosition!.longitude.toStringAsFixed(4)}';
      }

      final eventSummary = await CalendarService().buildTodaySummary();
      final String text = await _geminiService.generateDiaryText(
        photoTakenAt: takenAt,
        locationHint: locationHint,
        routeSummary: await _buildRouteSummaryForToday(),
        eventSummary: eventSummary,
      );
      setDiaryText(text);

      final Uint8List imageBytes = await _geminiService.generateIllustrationBytes(
        diaryText: text,
        fallbackImageBytes: _originalImageBytes ?? selectedBytes,
        enableCloud: _imageCloudEnabled,
        width: _imageWidth,
        height: _imageHeight,
        style: _imageStyle,
      );
      setGeneratedImage(imageBytes);

      final saved = await _persistEntry(
        text: text,
        imageBytes: imageBytes,
        photoTakenAt: takenAt,
      );
      if (!saved) {
        _setError('히스토리에 저장하지 못했습니다.');
      }
    } catch (_) {
      _setError('자동 생성 중 오류가 발생했습니다.');
    } finally {
      setLoading(false);
    }
  }

  Future<void> regenerateDiary() async {
    if (_isLoading) return;
    final Uint8List? base = _originalImageBytes;
    final DateTime? takenAt = _lastPhotoTakenAt;
    if (base == null || takenAt == null) {
      _setError('다시 생성할 원본이 없습니다. 먼저 이미지를 선택하세요.');
      return;
    }
    setLoading(true);
    try {
      String? locationHint;
      if (_lastPosition != null) {
        locationHint = _placeLabel ??
            '위도 ${_lastPosition!.latitude.toStringAsFixed(4)}, 경도 ${_lastPosition!.longitude.toStringAsFixed(4)}';
      }
      final eventSummary = await CalendarService().buildTodaySummary();
      final String text = await _geminiService.generateDiaryText(
        photoTakenAt: takenAt,
        locationHint: locationHint,
        routeSummary: await _buildRouteSummaryForToday(),
        eventSummary: eventSummary,
      );
      setDiaryText(text);

      final Uint8List imageBytes = await _geminiService.generateIllustrationBytes(
        diaryText: text,
        fallbackImageBytes: base,
        enableCloud: _imageCloudEnabled,
        width: _imageWidth,
        height: _imageHeight,
        style: _imageStyle,
      );
      setGeneratedImage(imageBytes);

      final saved = await _persistEntry(
        text: text,
        imageBytes: imageBytes,
        photoTakenAt: takenAt,
      );
      if (!saved) {
        _setError('히스토리에 저장하지 못했습니다.');
      }
    } catch (_) {
      _setError('다시 생성 중 오류가 발생했습니다.');
    } finally {
      setLoading(false);
    }
  }

  Future<String?> _buildRouteSummaryForToday() async {
    try {
      final now = DateTime.now();
      // Lazy import to avoid extra coupling at top
      // ignore: avoid_dynamic_calls
      final dynamic svc = await _loadLocationLogService();
      // ignore: avoid_dynamic_calls
      return await svc.buildRouteSummary(DateTime(now.year, now.month, now.day));
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _loadLocationLogService() async {
    // Direct import would be cleaner, but we keep it isolated
    // to reduce VM size impact when feature disabled.
    // This still compiles to static import; abstraction for clarity.
    // ignore: unnecessary_cast
    return (LocationLogService()) as dynamic;
  }

  Future<void> runAutoPipelineNow() async {
    if (_isLoading) return;
    setLoading(true);
    try {
      final pipeline = DailyPipeline(
        locationService: const LocationService(),
        photoService: const PhotoService(),
        viewModel: this,
      );
      await pipeline.runOnce();
    } catch (_) {
      _setError('자정 파이프라인 실행 중 오류가 발생했습니다.');
    } finally {
      setLoading(false);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _autoEnabled = prefs.getBool(_autoEnabledKey) ?? false;
    _wifiOnly = prefs.getBool(_wifiOnlyKey) ?? false;
    _samplingMinutes = prefs.getInt(_samplingMinutesKey) ?? 30;
    _notifyEnabled = prefs.getBool(_notifyEnabledKey) ?? true;
    _historyLimit = prefs.getInt(_historyLimitKey) ?? 100;
    _runHour = prefs.getInt(_runHourKey) ?? 0;
    _runMinute = prefs.getInt(_runMinuteKey) ?? 0;
    _imageCloudEnabled = prefs.getBool(_imgCloudKey) ?? true;
    _imageWidth = prefs.getInt(_imgWidthKey);
    _imageHeight = prefs.getInt(_imgHeightKey);
    _imageStyle = prefs.getString(_imgStyleKey);
    notifyListeners();
  }

  Future<void> setAutoEnabled(bool value) async {
    if (_autoEnabled == value) return;
    if (value) {
      // Ensure background location permission where applicable
      await _ensureBackgroundLocationPermission();
    }
    _autoEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoEnabledKey, _autoEnabled);
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    if (_wifiOnly == value) return;
    _wifiOnly = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wifiOnlyKey, _wifiOnly);
    notifyListeners();
  }

  Future<void> setSamplingMinutes(int minutes) async {
    if (minutes < 5) minutes = 5;
    _samplingMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_samplingMinutesKey, _samplingMinutes);
    notifyListeners();
  }

  Future<void> setNotifyEnabled(bool value) async {
    _notifyEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifyEnabledKey, _notifyEnabled);
    notifyListeners();
  }

  Future<void> sampleLocationNow() async {
    try {
      final pos = await _locationService.getCoarsePosition();
      if (pos == null) {
        _setError('위치 샘플링에 실패했습니다.');
        return;
      }
      final log = LocationLogService();
      final now = DateTime.now();
      await log.appendSample(LocationSample(latitude: pos.latitude, longitude: pos.longitude, timestamp: now));
      _lastSampleAt = now;
      notifyListeners();
    } catch (_) {
      _setError('위치 샘플링 중 오류가 발생했습니다.');
    }
  }

  Future<void> _ensureBackgroundLocationPermission() async {
    try {
      // On iOS/Android this maps to the appropriate setting
      PermissionStatus status = await Permission.locationAlways.status;
      if (!status.isGranted) {
        status = await Permission.locationAlways.request();
      }
    } catch (_) {
      // ignore
    }
  }

  Future<bool> _persistEntry({
    required String text,
    required Uint8List imageBytes,
    required DateTime photoTakenAt,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final String id = DateTime.now().millisecondsSinceEpoch.toString();
      final String imagePath = '${dir.path}/ai_diary_$id.png';
      final file = File(imagePath);
      await file.writeAsBytes(imageBytes, flush: true);

      final entry = DiaryEntry(
        id: id,
        text: text,
        imagePath: imagePath,
        createdAt: DateTime.now(),
        photoTakenAt: photoTakenAt,
        placeLabel: _placeLabel,
        latitude: _lastPosition?.latitude,
        longitude: _lastPosition?.longitude,
      );

      await _appendHistory(entry);
      await loadHistory();
      await _maybeTrimHistory();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> raw = prefs.getStringList(_historyPrefsKey) ?? <String>[];
      _history = raw.map(DiaryEntry.fromJsonString).toList(growable: false);
      notifyListeners();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _maybeTrimHistory() async {
    if (_history.length <= _historyLimit) return;
    final prefs = await SharedPreferences.getInstance();
    final List<DiaryEntry> trimmed = _history.take(_historyLimit).toList();
    await prefs.setStringList(
      _historyPrefsKey,
      trimmed.map((e) => e.toJsonString()).toList(),
    );
    // Delete orphaned files beyond limit is skipped for safety
    _history = trimmed;
    notifyListeners();
  }

  Future<void> setHistoryLimit(int value) async {
    if (value < 10) value = 10;
    _historyLimit = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_historyLimitKey, _historyLimit);
    await _maybeTrimHistory();
  }

  Future<void> setRunHour(int hour) async {
    if (hour < 0 || hour > 23) return;
    _runHour = hour;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_runHourKey, _runHour);
    notifyListeners();
  }

  Future<void> setRunMinute(int minute) async {
    if (minute < 0 || minute > 59) return;
    _runMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_runMinuteKey, _runMinute);
    notifyListeners();
  }

  Future<void> setRunTime({required int hour, required int minute}) async {
    if (hour < 0 || hour > 23) return;
    if (minute < 0 || minute > 59) return;
    _runHour = hour;
    _runMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_runHourKey, _runHour);
    await prefs.setInt(_runMinuteKey, _runMinute);
    notifyListeners();
  }

  Future<void> setImageCloudEnabled(bool value) async {
    _imageCloudEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_imgCloudKey, _imageCloudEnabled);
    notifyListeners();
  }

  Future<void> setImageResolution({int? width, int? height}) async {
    _imageWidth = width;
    _imageHeight = height;
    final prefs = await SharedPreferences.getInstance();
    if (width != null) {
      await prefs.setInt(_imgWidthKey, width);
    } else {
      await prefs.remove(_imgWidthKey);
    }
    if (height != null) {
      await prefs.setInt(_imgHeightKey, height);
    } else {
      await prefs.remove(_imgHeightKey);
    }
    notifyListeners();
  }

  Future<void> setImageStyle(String? value) async {
    _imageStyle = (value != null && value.trim().isNotEmpty) ? value.trim() : null;
    final prefs = await SharedPreferences.getInstance();
    if (_imageStyle != null) {
      await prefs.setString(_imgStyleKey, _imageStyle!);
    } else {
      await prefs.remove(_imgStyleKey);
    }
    notifyListeners();
  }

  Future<void> _appendHistory(DiaryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_historyPrefsKey) ?? <String>[];
    raw.insert(0, entry.toJsonString());
    await prefs.setStringList(_historyPrefsKey, raw);
  }

  Future<bool> deleteEntryById(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> raw = prefs.getStringList(_historyPrefsKey) ?? <String>[];
      final List<DiaryEntry> items = raw.map(DiaryEntry.fromJsonString).toList();
      DiaryEntry? target;
      for (final e in items) {
        if (e.id == id) {
          target = e;
          break;
        }
      }
      final List<DiaryEntry> kept = items.where((e) => e.id != id).toList();
      await prefs.setStringList(_historyPrefsKey, kept.map((e) => e.toJsonString()).toList());
      // delete file if exists
      if (target != null) {
        final f = File(target.imagePath);
        if (await f.exists()) {
          await f.delete();
        }
      }
      await loadHistory();
      return true;
    } catch (_) {
      _setError('항목을 삭제하지 못했습니다.');
      return false;
    }
  }

  Future<bool> clearHistory() async {
    try {
      // delete all files
      for (final e in _history) {
        try {
          final f = File(e.imagePath);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyPrefsKey);
      _history = const [];
      notifyListeners();
      return true;
    } catch (_) {
      _setError('히스토리를 모두 삭제하지 못했습니다.');
      return false;
    }
  }

  Future<bool> saveImageToGallery() async {
    try {
      final bytes = _generatedImageBytes;
      if (bytes == null || bytes.isEmpty) {
        _setError('저장할 이미지가 없습니다.');
        return false;
      }
      // image_gallery_saver expects Uint8List and optional name
      final String name = 'ai_diary_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await ImageGallerySaver.saveImage(bytes, name: name, quality: 100);
      final bool success = (result != null) && (result['isSuccess'] == true);
      if (!success) {
        _setError('갤러리에 저장하지 못했습니다.');
      }
      return success;
    } catch (_) {
      _setError('갤러리에 저장하는 중 오류가 발생했습니다.');
      return false;
    }
  }

  Future<File?> writeImageTempFile() async {
    try {
      final bytes = _generatedImageBytes;
      if (bytes == null || bytes.isEmpty) {
        _setError('공유할 이미지가 없습니다.');
        return null;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ai_diary_share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      _setError('임시 파일을 생성하지 못했습니다.');
      return null;
    }
  }

  Future<DateTime?> _readPhotoTakenAt(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final Map<String, IfdTag> data = await readExifFromBytes(bytes);
      if (data.isEmpty) return null;

      // Common EXIF datetime tags
      final candidates = <String?>[
        data['EXIF DateTimeOriginal']?.printable,
        data['EXIF DateTimeDigitized']?.printable,
        data['Image DateTime']?.printable,
      ];

      for (final raw in candidates) {
        final dt = _parseExifDateTime(raw);
        if (dt != null) return dt;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  DateTime? _parseExifDateTime(String? value) {
    if (value == null) return null;
    // Expected formats: 'YYYY:MM:DD HH:MM:SS' or variations
    final normalized = value.trim().replaceAll('-', ':');
    final parts = normalized.split(' ');
    if (parts.length != 2) return null;
    final datePart = parts[0].split(':');
    final timePart = parts[1].split(':');
    if (datePart.length < 3 || timePart.length < 2) return null;
    try {
      final year = int.parse(datePart[0]);
      final month = int.parse(datePart[1]);
      final day = int.parse(datePart[2]);
      final hour = int.parse(timePart[0]);
      final minute = int.parse(timePart[1]);
      final second = timePart.length >= 3 ? int.tryParse(timePart[2]) ?? 0 : 0;
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}

class PositionData {
  final double latitude;
  final double longitude;
  const PositionData({required this.latitude, required this.longitude});
}


