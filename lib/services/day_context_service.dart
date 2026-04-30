import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../models/day_context.dart';
import 'calendar_service.dart';
import 'photo_service.dart';

class DayContextService {
  final CalendarService calendarService;
  final PhotoService photoService;

  const DayContextService({
    required this.calendarService,
    required this.photoService,
  });

  Future<DayContext> buildTodayContext() async {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day);
    final events = await calendarService.fetchTodayEventsLite();
    final photos = await photoService.fetchTodayPhotos();
    final sortedPhotos = List<AssetEntity>.of(photos)
      ..sort((a, b) => a.createDateTime.compareTo(b.createDateTime));

    final segments = <DaySegment>[];
    final usedPhotoIds = <String>{};

    for (final event in events) {
      final eventEnd = event.end ?? event.start.add(const Duration(hours: 1));
      final matchedPhotos = _photosNearEvent(sortedPhotos, event.start, eventEnd);
      usedPhotoIds.addAll(matchedPhotos.map((asset) => asset.id));
      segments.add(
        DaySegment(
          start: event.start,
          end: eventEnd,
          title: event.title,
          source: 'calendar',
          calendarName: event.calendarName,
          photoCount: matchedPhotos.length,
          placeHint: _firstPlaceHint(matchedPhotos) ?? event.location,
          confidence: matchedPhotos.isEmpty ? 0.68 : 0.9,
        ),
      );
    }

    final unmatchedPhotos = sortedPhotos.where((asset) => !usedPhotoIds.contains(asset.id)).toList();
    for (final cluster in _clusterPhotos(unmatchedPhotos)) {
      segments.add(
        DaySegment(
          start: cluster.start,
          end: cluster.end,
          title: _inferPhotoOnlyTitle(cluster),
          source: 'photo',
          photoCount: cluster.assets.length,
          placeHint: _firstPlaceHint(cluster.assets),
          confidence: cluster.assets.length >= 3 ? 0.72 : 0.56,
        ),
      );
    }

    segments.sort((a, b) => a.start.compareTo(b.start));
    final representative = await _loadRepresentativeImage(sortedPhotos, segments);

    return DayContext(
      date: date,
      segments: segments,
      representativeImageBytes: representative,
    );
  }

  List<AssetEntity> _photosNearEvent(List<AssetEntity> photos, DateTime start, DateTime end) {
    final windowStart = start.subtract(const Duration(minutes: 45));
    final windowEnd = end.add(const Duration(minutes: 45));
    return photos.where((asset) {
      final takenAt = asset.createDateTime;
      return !takenAt.isBefore(windowStart) && !takenAt.isAfter(windowEnd);
    }).toList();
  }

  List<_PhotoCluster> _clusterPhotos(List<AssetEntity> photos) {
    if (photos.isEmpty) return const [];
    final clusters = <_PhotoCluster>[];
    var current = <AssetEntity>[photos.first];

    for (final photo in photos.skip(1)) {
      final previous = current.last;
      final gap = photo.createDateTime.difference(previous.createDateTime).abs();
      final samePlace = _isNearby(previous, photo);
      if (gap <= const Duration(minutes: 75) || samePlace) {
        current.add(photo);
      } else {
        clusters.add(_PhotoCluster(current));
        current = <AssetEntity>[photo];
      }
    }
    clusters.add(_PhotoCluster(current));
    return clusters.where((cluster) => cluster.assets.isNotEmpty).toList(growable: false);
  }

  bool _isNearby(AssetEntity a, AssetEntity b) {
    final alat = a.latitude;
    final alon = a.longitude;
    final blat = b.latitude;
    final blon = b.longitude;
    if (alat == null || alon == null || blat == null || blon == null) return false;
    if (alat == 0 || alon == 0 || blat == 0 || blon == 0) return false;
    final latDiff = (alat - blat).abs();
    final lonDiff = (alon - blon).abs();
    return latDiff < 0.003 && lonDiff < 0.003;
  }

  String _inferPhotoOnlyTitle(_PhotoCluster cluster) {
    final hour = cluster.start.hour;
    if (hour >= 6 && hour < 11) return '오전의 기록';
    if (hour >= 11 && hour < 14) return '점심 무렵의 순간';
    if (hour >= 14 && hour < 18) return '오후에 머문 곳';
    if (hour >= 18 && hour < 22) return '저녁의 장면';
    return '하루의 조용한 순간';
  }

  String? _firstPlaceHint(List<AssetEntity> photos) {
    for (final photo in photos) {
      final lat = photo.latitude;
      final lon = photo.longitude;
      if (lat == null || lon == null || lat == 0 || lon == 0) continue;
      return '위도 ${lat.toStringAsFixed(4)}, 경도 ${lon.toStringAsFixed(4)}';
    }
    return null;
  }

  Future<Uint8List?> _loadRepresentativeImage(List<AssetEntity> photos, List<DaySegment> segments) async {
    if (photos.isEmpty) return null;
    final preferredHour = segments.isEmpty ? 14 : segments.first.start.hour;
    final scored = List<AssetEntity>.of(photos)
      ..sort((a, b) {
        final aScore = (a.createDateTime.hour - preferredHour).abs() + (a.width * a.height == 0 ? 100 : 0);
        final bScore = (b.createDateTime.hour - preferredHour).abs() + (b.width * b.height == 0 ? 100 : 0);
        return aScore.compareTo(bScore);
      });
    for (final asset in scored.take(8)) {
      final bytes = await asset.originBytes;
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
    return null;
  }
}

class _PhotoCluster {
  final List<AssetEntity> assets;

  const _PhotoCluster(this.assets);

  DateTime get start => assets.first.createDateTime;
  DateTime get end => assets.last.createDateTime;
}
