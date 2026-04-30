import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/day_context.dart';
import '../models/diary_entry.dart';
import '../services/calendar_service.dart';
import '../services/daily_pipeline.dart';
import '../services/day_context_service.dart';
import '../services/gemini_service.dart';
import '../services/location_log_service.dart';
import '../services/location_service.dart';
import '../services/photo_service.dart';

class HomeViewModel extends ChangeNotifier {
  final ImagePicker _imagePicker = ImagePicker();
  final GeminiService _geminiService = GeminiService();
  final LocationService _locationService = const LocationService();
  final DayContextService _dayContextService = DayContextService(
    calendarService: CalendarService(),
    photoService: const PhotoService(),
  );

  bool _isLoading = false;
  bool _isContextLoading = false;
  String? _diaryText;
  Uint8List? _generatedImageBytes;
  Uint8List? _originalImageBytes;
  Uint8List? _todayRepresentativeImageBytes;
  DateTime? _lastPhotoTakenAt;
  bool _showOriginal = false;
  String? _lastError;

  String _mood = '평온';
  String _tone = '감성적으로';
  String _scheduleText = '';
  String _memo = '';
  List<XFile> _selectedPhotos = const [];
  List<Uint8List> _selectedPhotoBytes = const [];
  List<DaySegment> _todaySegments = const [];
  String _todayContextSummary = '';

  PositionData? _lastPosition;
  String? _placeLabel;
  List<DiaryEntry> _history = const [];

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

  bool _autoEnabled = false;
  bool _wifiOnly = false;
  int _samplingMinutes = 30;
  bool _notifyEnabled = true;
  int _historyLimit = 100;
  DateTime? _lastSampleAt;
  int _runHour = 23;
  int _runMinute = 0;
  bool _imageCloudEnabled = false;
  int? _imageWidth;
  int? _imageHeight;
  String? _imageStyle;

  bool get isLoading => _isLoading;
  bool get isContextLoading => _isContextLoading;
  String? get diaryText => _diaryText;
  Uint8List? get generatedImageBytes => _generatedImageBytes;
  Uint8List? get originalImageBytes => _originalImageBytes;
  Uint8List? get todayRepresentativeImageBytes => _todayRepresentativeImageBytes;
  bool get showOriginal => _showOriginal;
  String? get lastError => _lastError;
  String get mood => _mood;
  String get tone => _tone;
  String get scheduleText => _scheduleText;
  String get memo => _memo;
  List<XFile> get selectedPhotos => _selectedPhotos;
  List<Uint8List> get selectedPhotoBytes => _selectedPhotoBytes;
  List<DaySegment> get todaySegments => _todaySegments;
  String get todayContextSummary => _todayContextSummary;
  PositionData? get lastPosition => _lastPosition;
  String? get placeLabel => _placeLabel;
  List<DiaryEntry> get history => _history;
  bool get autoEnabled => _autoEnabled;
  bool get wifiOnly => _wifiOnly;
  int get samplingMinutes => _samplingMinutes;
  bool get notifyEnabled => _notifyEnabled;
  int get historyLimit => _historyLimit;
  DateTime? get lastSampleAt => _lastSampleAt;
  int get runHour => _runHour;
  int get runMinute => _runMinute;
  bool get imageCloudEnabled => _imageCloudEnabled;
  int? get imageWidth => _imageWidth;
  int? get imageHeight => _imageHeight;
  String? get imageStyle => _imageStyle;

  Future<void> initialize() async {
    await loadHistory();
    await _loadSettings();
    await requestLocationAndFetch();
    await refreshTodayContext();
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
  }

  Future<void> refreshTodayContext() async {
    if (_isContextLoading) return;
    _isContextLoading = true;
    notifyListeners();
    try {
      final context = await _dayContextService.buildTodayContext();
      _todaySegments = context.segments;
      _todayContextSummary = context.toPromptSummary();
      _todayRepresentativeImageBytes = context.representativeImageBytes;
      if (_selectedPhotoBytes.isEmpty && _todayRepresentativeImageBytes != null) {
        _originalImageBytes = _todayRepresentativeImageBytes;
        _generatedImageBytes = _todayRepresentativeImageBytes;
      }
      if (_lastPhotoTakenAt == null && context.segments.isNotEmpty) {
        _lastPhotoTakenAt = context.segments.first.start;
      }
    } catch (_) {
      _setError('오늘의 흐름을 불러오지 못했습니다. 사진/캘린더 권한을 확인해 주세요.');
    } finally {
      _isContextLoading = false;
      notifyListeners();
    }
  }

  void setMood(String value) {
    if (_mood == value) return;
    _mood = value;
    notifyListeners();
  }

  void setTone(String value) {
    if (_tone == value) return;
    _tone = value;
    notifyListeners();
  }

  void setScheduleText(String value) {
    _scheduleText = value;
  }

  void setMemo(String value) {
    _memo = value;
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

  Future<void> pickPhotos() async {
    try {
      final photos = await _imagePicker.pickMultiImage(imageQuality: 92);
      if (photos.isEmpty) return;
      final bytes = <Uint8List>[];
      for (final photo in photos) {
        bytes.add(await photo.readAsBytes());
      }
      _selectedPhotos = photos;
      _selectedPhotoBytes = bytes;
      _originalImageBytes = bytes.first;
      _generatedImageBytes = bytes.first;
      _lastPhotoTakenAt = await _readPhotoTakenAt(photos.first) ?? DateTime.now();
      _showOriginal = false;
      notifyListeners();
    } catch (_) {
      _setError('사진을 불러오지 못했습니다. 권한을 확인해 주세요.');
    }
  }

  void clearSelectedPhotos() {
    _selectedPhotos = const [];
    _selectedPhotoBytes = const [];
    _originalImageBytes = _todayRepresentativeImageBytes;
    _generatedImageBytes = _todayRepresentativeImageBytes;
    notifyListeners();
  }

  Future<void> createAiDiary() async {
    await pickPhotos();
    if (_selectedPhotoBytes.isNotEmpty || _todayRepresentativeImageBytes != null) {
      await createDailyDiary();
    }
  }

  Future<void> createDailyDiary() async {
    if (_isLoading) return;
    final activePhotoBytes = _selectedPhotoBytes.isNotEmpty
        ? _selectedPhotoBytes
        : (_todayRepresentativeImageBytes == null ? const <Uint8List>[] : <Uint8List>[_todayRepresentativeImageBytes!]);
    if (activePhotoBytes.isEmpty) {
      _setError('오늘 사진을 찾지 못했습니다. 사진을 직접 선택하거나 사진첩 권한을 확인해 주세요.');
      return;
    }

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final takenAt = _lastPhotoTakenAt ?? DateTime.now();
      final locationHint = _lastPosition == null
          ? null
          : (_placeLabel ??
              '위도 ${_lastPosition!.latitude.toStringAsFixed(4)}, 경도 ${_lastPosition!.longitude.toStringAsFixed(4)}');
      final routeSummary = await _buildRouteSummaryForToday();
      final eventSummary = await CalendarService().buildTodaySummary();
      final scheduleSource = _scheduleText.trim().isNotEmpty
          ? _scheduleText
          : (_todayContextSummary.trim().isNotEmpty ? _todayContextSummary : (eventSummary ?? ''));

      final text = await _geminiService.generateDiaryFromInputs(
        date: takenAt,
        mood: _mood,
        tone: _tone,
        scheduleText: scheduleSource,
        memo: _memo,
        photoCount: activePhotoBytes.length,
        locationHint: locationHint,
        routeSummary: routeSummary,
        eventSummary: eventSummary,
      );
      _diaryText = text;

      final imageBytes = await _geminiService.generateIllustrationBytes(
        diaryText: text,
        fallbackImageBytes: activePhotoBytes.first,
        enableCloud: false,
        width: _imageWidth,
        height: _imageHeight,
        style: _imageStyle,
      );
      _generatedImageBytes = imageBytes;
      _originalImageBytes ??= activePhotoBytes.first;

      final saved = await _persistEntry(
        text: text,
        imageBytes: imageBytes,
        photoTakenAt: takenAt,
      );
      if (!saved) {
        _setError('히스토리에 저장하지 못했습니다.');
      }
    } catch (_) {
      _setError('다이어리 생성 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> generateFromAuto(Uint8List selectedBytes, DateTime takenAt) async {
    _selectedPhotoBytes = [selectedBytes];
    _selectedPhotos = const [];
    _originalImageBytes = selectedBytes;
    _generatedImageBytes = selectedBytes;
    _lastPhotoTakenAt = takenAt;
    await createDailyDiary();
  }

  Future<void> regenerateDiary() async {
    if (_selectedPhotoBytes.isEmpty && _originalImageBytes != null) {
      _selectedPhotoBytes = [_originalImageBytes!];
    }
    await createDailyDiary();
  }

  Future<String?> _buildRouteSummaryForToday() async {
    try {
      final now = DateTime.now();
      return await LocationLogService().buildRouteSummary(DateTime(now.year, now.month, now.day));
    } catch (_) {
      return null;
    }
  }

  Future<void> runAutoPipelineNow() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final pipeline = DailyPipeline(
        locationService: const LocationService(),
        photoService: const PhotoService(),
        viewModel: this,
      );
      await pipeline.runOnce();
    } catch (_) {
      _setError('자동 생성 실행 중 오류가 발생했습니다.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _autoEnabled = prefs.getBool(_autoEnabledKey) ?? false;
    _wifiOnly = prefs.getBool(_wifiOnlyKey) ?? false;
    _samplingMinutes = prefs.getInt(_samplingMinutesKey) ?? 30;
    _notifyEnabled = prefs.getBool(_notifyEnabledKey) ?? true;
    _historyLimit = prefs.getInt(_historyLimitKey) ?? 100;
    _runHour = prefs.getInt(_runHourKey) ?? 23;
    _runMinute = prefs.getInt(_runMinuteKey) ?? 0;
    _imageCloudEnabled = false;
    _imageWidth = prefs.getInt(_imgWidthKey);
    _imageHeight = prefs.getInt(_imgHeightKey);
    _imageStyle = prefs.getString(_imgStyleKey) ?? 'pastel watercolor diary';
    notifyListeners();
  }

  Future<void> setAutoEnabled(bool value) async {
    if (value) await _ensureBackgroundLocationPermission();
    _autoEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoEnabledKey, _autoEnabled);
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    _wifiOnly = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wifiOnlyKey, _wifiOnly);
    notifyListeners();
  }

  Future<void> setSamplingMinutes(int minutes) async {
    _samplingMinutes = minutes < 5 ? 5 : minutes;
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
      final now = DateTime.now();
      await LocationLogService().appendSample(
        LocationSample(latitude: pos.latitude, longitude: pos.longitude, timestamp: now),
      );
      _lastSampleAt = now;
      notifyListeners();
    } catch (_) {
      _setError('위치 샘플링 중 오류가 발생했습니다.');
    }
  }

  Future<void> _ensureBackgroundLocationPermission() async {
    try {
      PermissionStatus status = await Permission.locationAlways.status;
      if (!status.isGranted) {
        await Permission.locationAlways.request();
      }
    } catch (_) {}
  }

  Future<bool> _persistEntry({
    required String text,
    required Uint8List imageBytes,
    required DateTime photoTakenAt,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final imagePath = '${dir.path}/harugyeol_$id.jpg';
      await File(imagePath).writeAsBytes(imageBytes, flush: true);

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
      final raw = prefs.getStringList(_historyPrefsKey) ?? <String>[];
      _history = raw.map(DiaryEntry.fromJsonString).toList(growable: false);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _appendHistory(DiaryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyPrefsKey) ?? <String>[];
    raw.insert(0, entry.toJsonString());
    await prefs.setStringList(_historyPrefsKey, raw);
  }

  Future<void> _maybeTrimHistory() async {
    if (_history.length <= _historyLimit) return;
    final prefs = await SharedPreferences.getInstance();
    final trimmed = _history.take(_historyLimit).toList();
    await prefs.setStringList(_historyPrefsKey, trimmed.map((e) => e.toJsonString()).toList());
    _history = trimmed;
    notifyListeners();
  }

  Future<void> setHistoryLimit(int value) async {
    _historyLimit = value < 10 ? 10 : value;
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
    await setRunHour(hour);
    await setRunMinute(minute);
  }

  Future<void> setImageCloudEnabled(bool value) async {
    _imageCloudEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_imgCloudKey, false);
    notifyListeners();
  }

  Future<void> setImageResolution({int? width, int? height}) async {
    _imageWidth = width;
    _imageHeight = height;
    final prefs = await SharedPreferences.getInstance();
    if (width == null) {
      await prefs.remove(_imgWidthKey);
    } else {
      await prefs.setInt(_imgWidthKey, width);
    }
    if (height == null) {
      await prefs.remove(_imgHeightKey);
    } else {
      await prefs.setInt(_imgHeightKey, height);
    }
    notifyListeners();
  }

  Future<void> setImageStyle(String? value) async {
    _imageStyle = (value != null && value.trim().isNotEmpty) ? value.trim() : null;
    final prefs = await SharedPreferences.getInstance();
    if (_imageStyle == null) {
      await prefs.remove(_imgStyleKey);
    } else {
      await prefs.setString(_imgStyleKey, _imageStyle!);
    }
    notifyListeners();
  }

  Future<bool> deleteEntryById(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_historyPrefsKey) ?? <String>[];
      final items = raw.map(DiaryEntry.fromJsonString).toList();
      DiaryEntry? target;
      for (final item in items) {
        if (item.id == id) target = item;
      }
      final kept = items.where((item) => item.id != id).toList();
      await prefs.setStringList(_historyPrefsKey, kept.map((e) => e.toJsonString()).toList());
      if (target != null) {
        final file = File(target.imagePath);
        if (await file.exists()) await file.delete();
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
      for (final entry in _history) {
        try {
          final file = File(entry.imagePath);
          if (await file.exists()) await file.delete();
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
      final name = 'harugyeol_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await ImageGallerySaver.saveImage(bytes, name: name, quality: 100);
      final success = result != null && result['isSuccess'] == true;
      if (!success) _setError('갤러리에 저장하지 못했습니다.');
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
      final file = File('${dir.path}/harugyeol_share_${DateTime.now().millisecondsSinceEpoch}.jpg');
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
      final data = await readExifFromBytes(bytes);
      final candidates = <String?>[
        data['EXIF DateTimeOriginal']?.printable,
        data['EXIF DateTimeDigitized']?.printable,
        data['Image DateTime']?.printable,
      ];
      for (final raw in candidates) {
        final dt = _parseExifDateTime(raw);
        if (dt != null) return dt;
      }
    } catch (_) {}
    return null;
  }

  DateTime? _parseExifDateTime(String? value) {
    if (value == null) return null;
    final normalized = value.trim().replaceAll('-', ':');
    final parts = normalized.split(' ');
    if (parts.length != 2) return null;
    final datePart = parts[0].split(':');
    final timePart = parts[1].split(':');
    if (datePart.length < 3 || timePart.length < 2) return null;
    try {
      return DateTime(
        int.parse(datePart[0]),
        int.parse(datePart[1]),
        int.parse(datePart[2]),
        int.parse(timePart[0]),
        int.parse(timePart[1]),
        timePart.length >= 3 ? int.tryParse(timePart[2]) ?? 0 : 0,
      );
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
