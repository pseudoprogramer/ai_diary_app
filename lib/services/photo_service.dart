import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:photo_manager/photo_manager.dart';

class PhotoService {
  const PhotoService();

  Future<List<AssetEntity>> fetchTodayPhotos() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
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

  // Select an "important" photo by simple heuristics: larger size and mid-day proximity
  Future<AssetEntity?> chooseImportant(List<AssetEntity> assets) async {
    if (assets.isEmpty) return null;
    double bestScore = -1;
    AssetEntity? best;
    for (final a in assets) {
      final dt = a.createDateTime;
      final int hour = dt.hour;
      // mid-day bonus
      final double middayScore = 1.0 - ((hour - 12).abs() / 12.0);
      // resolution bonus
      final s = await a.originBytes;
      final double sizeScore = s == null ? 0 : (s.length / (1024 * 1024)).clamp(0, 10).toDouble() / 10.0;
      final double score = middayScore * 0.6 + sizeScore * 0.4;
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    return best ?? assets.first;
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
    final List<AssetEntity> sorted = List.of(assets)
      ..sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    final List<AssetEntity> picked = [];
    final Set<String> usedIds = {};

    AssetEntity? nearestTo(DateTime t) {
      Duration best = const Duration(days: 365);
      AssetEntity? bestA;
      for (final a in sorted) {
        final d = (a.createDateTime.difference(t)).abs();
        if (d < best) {
          best = d;
          bestA = a;
        }
      }
      return bestA;
    }

    for (final t in eventTimes.take(2)) {
      final n = nearestTo(t);
      if (n != null && !usedIds.contains(n.id)) {
        picked.add(n);
        usedIds.add(n.id);
      }
      if (picked.length >= maxCount) return picked;
    }

    double scoreOf(AssetEntity a, int bytesLen) {
      final int hour = a.createDateTime.hour;
      final double middayScore = 1.0 - ((hour - 12).abs() / 12.0);
      final double sizeScore = (bytesLen / (1024 * 1024)).clamp(0, 10).toDouble() / 10.0;
      return middayScore * 0.6 + sizeScore * 0.4;
    }

    final List<_Scored> candidates = [];
    for (final a in sorted) {
      if (usedIds.contains(a.id)) continue;
      // Avoid heavy originBytes read; approximate size using width*height
      final int lenApprox = (a.width * a.height) ~/ 4; // 4 bytes per pixel rough
      candidates.add(_Scored(a, scoreOf(a, lenApprox)));
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));

    bool farFromPicked(DateTime t) {
      for (final p in picked) {
        if ((p.createDateTime.difference(t)).abs() < minGap) return false;
      }
      return true;
    }

    for (final c in candidates) {
      if (picked.length >= maxCount) break;
      if (farFromPicked(c.asset.createDateTime)) picked.add(c.asset);
    }
    return picked;
  }

}

class _Scored {
  final AssetEntity asset;
  final double score;
  _Scored(this.asset, this.score);
}



