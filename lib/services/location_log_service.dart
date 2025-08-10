import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class LocationSample {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  const LocationSample({required this.latitude, required this.longitude, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        'ts': timestamp.toIso8601String(),
      };

  static LocationSample fromJson(Map<String, dynamic> json) => LocationSample(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
        timestamp: DateTime.parse(json['ts'] as String),
      );
}

class LocationLogService {
  static String _keyForDay(DateTime day) =>
      'loc_log_${day.year.toString().padLeft(4, '0')}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';

  Future<void> appendSample(LocationSample s) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = _keyForDay(s.timestamp);
    final List<String> raw = prefs.getStringList(key) ?? <String>[];
    raw.add(jsonEncode(s.toJson()));
    await prefs.setStringList(key, raw);
  }

  Future<List<LocationSample>> readSamples(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = _keyForDay(day);
    final List<String> raw = prefs.getStringList(key) ?? <String>[];
    return raw.map((s) => LocationSample.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
  }

  Future<String?> buildRouteSummary(DateTime day) async {
    final samples = await readSamples(day);
    if (samples.length < 2) return null;
    double totalKm = 0;
    for (int i = 1; i < samples.length; i++) {
      totalKm += _distanceKm(samples[i - 1].latitude, samples[i - 1].longitude, samples[i].latitude, samples[i].longitude);
    }
    final double rounded = double.parse(totalKm.toStringAsFixed(1));
    return '오늘 이동 스냅샷: 총 이동거리 약 ${rounded}km';
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0; // km
    final double dLat = _deg2rad(lat2 - lat1);
    final double dLon = _deg2rad(lon2 - lon1);
    final double a =
        (sin(dLat / 2) * sin(dLat / 2)) + cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * (sin(dLon / 2) * sin(dLon / 2));
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (3.1415926535897932 / 180.0);
}


