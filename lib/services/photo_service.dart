import 'dart:math' as math;
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

class PhotoService {
  const PhotoService();

  static const PermissionRequestOption _fullPhotoAccessOption =
      PermissionRequestOption(
    iosAccessLevel: IosAccessLevel.readWrite,
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  Future<PermissionState> requestFullPhotoAccess() {
    return PhotoManager.requestPermissionExtend(
      requestOption: _fullPhotoAccessOption,
    );
  }

  Future<PermissionState> getPhotoAccessState() {
    return PhotoManager.getPermissionState(
      requestOption: _fullPhotoAccessOption,
    );
  }

  Future<bool> hasFullPhotoAccess() async {
    final state = await getPhotoAccessState();
    return state == PermissionState.authorized;
  }

  Future<List<AssetEntity>> fetchTodayPhotos() async {
    final PermissionState ps = await requestFullPhotoAccess();
    if (!ps.hasAccess) return [];

    final DateTime now = DateTime.now();
    final DateTime start = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final FilterOptionGroup option = FilterOptionGroup(
      imageOption: const FilterOption(),
      orders: [
        const OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
      createTimeCond: DateTimeCond(min: start, max: end),
    );
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: option,
    );
    final List<AssetEntity> assets = [];
    for (final p in paths) {
      final list = await p.getAssetListPaged(page: 0, size: 400);
      assets.addAll(list);
    }
    return assets;
  }

  Future<DateTime?> tryExtractExifDate(AssetEntity asset) async {
    try {
      final Uint8List? bytes = await asset.originBytes;
      if (bytes == null) return null;
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

  // Select an important photo without asking the user. The ranking favors
  // calendar-adjacent moments, repeated photo clusters, and usable image quality.
  Future<AssetEntity?> chooseImportant(List<AssetEntity> assets) async {
    return chooseRepresentative(assets);
  }

  Future<AssetEntity?> chooseRepresentative(
    List<AssetEntity> assets, {
    List<DateTime> eventTimes = const [],
  }) async {
    if (assets.isEmpty) return null;
    final ranked = await _rankedCandidates(assets, eventTimes: eventTimes);
    return ranked.isEmpty ? assets.first : ranked.first.asset;
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

  Future<List<AssetEntity>> chooseImportantSet(
    List<AssetEntity> assets, {
    required int maxCount,
    List<DateTime> eventTimes = const [],
    Duration minGap = const Duration(minutes: 90),
  }) async {
    if (assets.isEmpty || maxCount <= 0) return [];
    final ranked = await _rankedCandidates(assets, eventTimes: eventTimes);
    if (ranked.isEmpty) return [];

    final List<AssetEntity> picked = [];
    final Set<String> usedIds = {};

    bool farFromPicked(DateTime t) {
      for (final p in picked) {
        if ((p.createDateTime.difference(t)).abs() < minGap) return false;
      }
      return true;
    }

    for (final t in eventTimes.take(3)) {
      _Scored? bestNearEvent;
      for (final candidate in ranked) {
        final gap = candidate.asset.createDateTime.difference(t).abs();
        if (gap > const Duration(hours: 2)) continue;
        if (usedIds.contains(candidate.asset.id)) continue;
        if (!farFromPicked(candidate.asset.createDateTime)) continue;
        bestNearEvent = candidate;
        break;
      }
      if (bestNearEvent != null) {
        picked.add(bestNearEvent.asset);
        usedIds.add(bestNearEvent.asset.id);
      }
      if (picked.length >= maxCount) return picked;
    }

    for (final c in ranked) {
      if (picked.length >= maxCount) break;
      if (usedIds.contains(c.asset.id)) continue;
      if (farFromPicked(c.asset.createDateTime)) picked.add(c.asset);
    }
    return picked;
  }

  Future<List<_Scored>> _rankedCandidates(
    List<AssetEntity> assets, {
    required List<DateTime> eventTimes,
  }) async {
    if (assets.isEmpty) return const [];

    final metadataRanked = assets
        .map((asset) => _Scored(
              asset,
              _metadataScore(asset, assets: assets, eventTimes: eventTimes),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final sampledIds =
        metadataRanked.take(24).map((item) => item.asset.id).toSet();
    final rescored = <_Scored>[];
    for (final item in metadataRanked) {
      var score = item.score;
      if (sampledIds.contains(item.asset.id)) {
        final quality = await _thumbnailQualityScore(item.asset);
        score = score * 0.72 + quality * 0.28;
      }
      rescored.add(_Scored(item.asset, score));
    }
    rescored.sort((a, b) => b.score.compareTo(a.score));
    return rescored;
  }

  double _metadataScore(
    AssetEntity asset, {
    required List<AssetEntity> assets,
    required List<DateTime> eventTimes,
  }) {
    final resolutionScore = _resolutionScore(asset);
    final aspectScore = _aspectScore(asset);
    final timeScore = _timeOfDayScore(asset.createDateTime);
    final eventScore = _eventProximityScore(asset.createDateTime, eventTimes);
    final clusterScore = _momentClusterScore(asset, assets);

    return resolutionScore * 0.18 +
        aspectScore * 0.12 +
        timeScore * 0.08 +
        eventScore * 0.28 +
        clusterScore * 0.34;
  }

  double _resolutionScore(AssetEntity asset) {
    final pixels = asset.width * asset.height;
    if (pixels <= 0) return 0.2;
    final megapixels = pixels / 1000000.0;
    return (math.log(megapixels + 1) / math.log(13)).clamp(0.0, 1.0);
  }

  double _aspectScore(AssetEntity asset) {
    if (asset.width <= 0 || asset.height <= 0) return 0.5;
    final ratio = asset.width > asset.height
        ? asset.width / asset.height
        : asset.height / asset.width;
    if (ratio <= 1.8) return 1.0;
    if (ratio <= 2.4) return 0.65;
    return 0.25;
  }

  double _timeOfDayScore(DateTime takenAt) {
    final hour = takenAt.hour + takenAt.minute / 60.0;
    if (hour >= 7 && hour <= 23) return 1.0;
    if (hour >= 5 && hour < 7) return 0.72;
    return 0.48;
  }

  double _eventProximityScore(DateTime takenAt, List<DateTime> eventTimes) {
    if (eventTimes.isEmpty) return 0.55;
    var bestMinutes = 240.0;
    for (final eventTime in eventTimes) {
      final minutes = takenAt.difference(eventTime).inMinutes.abs().toDouble();
      if (minutes < bestMinutes) bestMinutes = minutes;
    }
    if (bestMinutes <= 20) return 1.0;
    if (bestMinutes <= 90) return 1.0 - ((bestMinutes - 20) / 70) * 0.32;
    if (bestMinutes <= 180) return 0.5 - ((bestMinutes - 90) / 90) * 0.24;
    return 0.22;
  }

  double _momentClusterScore(AssetEntity asset, List<AssetEntity> assets) {
    var count = 0;
    for (final other in assets) {
      final gap = asset.createDateTime.difference(other.createDateTime).abs();
      if (gap <= const Duration(minutes: 75) || _isNearby(asset, other)) {
        count += 1;
      }
    }
    if (count <= 1) return 0.28;
    if (count == 2) return 0.58;
    if (count <= 5) return 0.82;
    return 1.0;
  }

  bool _isNearby(AssetEntity a, AssetEntity b) {
    final alat = a.latitude;
    final alon = a.longitude;
    final blat = b.latitude;
    final blon = b.longitude;
    if (alat == null || alon == null || blat == null || blon == null) {
      return false;
    }
    if (alat == 0 || alon == 0 || blat == 0 || blon == 0) return false;
    return (alat - blat).abs() < 0.003 && (alon - blon).abs() < 0.003;
  }

  Future<double> _thumbnailQualityScore(AssetEntity asset) async {
    try {
      final data = await asset.thumbnailDataWithSize(
        const ThumbnailSize(256, 256),
        quality: 76,
      );
      if (data == null || data.isEmpty) return 0.45;
      final decoded = img.decodeImage(data);
      if (decoded == null || decoded.width < 24 || decoded.height < 24) {
        return 0.35;
      }

      var count = 0;
      var lumaSum = 0.0;
      var lumaSqSum = 0.0;
      var colorSum = 0.0;
      var edgeSum = 0.0;
      final stepX = math.max(1, decoded.width ~/ 42);
      final stepY = math.max(1, decoded.height ~/ 42);

      for (var y = 0; y < decoded.height; y += stepY) {
        for (var x = 0; x < decoded.width; x += stepX) {
          final pixel = decoded.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();
          final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          lumaSum += luma;
          lumaSqSum += luma * luma;
          colorSum += ((r - g).abs() + (g - b).abs() + (b - r).abs()) / 3.0;

          final nx = math.min(decoded.width - 1, x + stepX);
          final ny = math.min(decoded.height - 1, y + stepY);
          final neighbor = decoded.getPixel(nx, ny);
          final nr = neighbor.r.toDouble();
          final ng = neighbor.g.toDouble();
          final nb = neighbor.b.toDouble();
          final neighborLuma = 0.2126 * nr + 0.7152 * ng + 0.0722 * nb;
          edgeSum += (luma - neighborLuma).abs();
          count += 1;
        }
      }

      if (count == 0) return 0.45;
      final mean = lumaSum / count;
      final variance = math.max(0, lumaSqSum / count - mean * mean);
      final contrast = math.sqrt(variance);
      final colorfulness = colorSum / count;
      final edgeDetail = edgeSum / count;

      final brightnessScore = 1.0 - ((mean - 132).abs() / 132).clamp(0.0, 1.0);
      final contrastScore = (contrast / 58).clamp(0.0, 1.0);
      final colorScore = (colorfulness / 42).clamp(0.0, 1.0);
      final detailScore = (edgeDetail / 24).clamp(0.0, 1.0);

      return brightnessScore * 0.32 +
          contrastScore * 0.26 +
          colorScore * 0.18 +
          detailScore * 0.24;
    } catch (_) {
      return 0.45;
    }
  }
}

class _Scored {
  final AssetEntity asset;
  final double score;
  _Scored(this.asset, this.score);
}
