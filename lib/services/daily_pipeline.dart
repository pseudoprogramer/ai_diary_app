import 'dart:typed_data';

import '../viewmodels/home_viewmodel.dart';
import 'location_service.dart';
import 'photo_service.dart';
import 'calendar_service.dart';

class DailyPipeline {
  final LocationService locationService;
  final PhotoService photoService;
  final HomeViewModel viewModel;

  DailyPipeline({
    required this.locationService,
    required this.photoService,
    required this.viewModel,
  });

  // Simplified MVP: pick the most recent photo of the day, build prompt with rough location
  Future<void> runOnce() async {
    // 1) Fetch coarse location for context and update VM label
    final pos = await locationService.getCoarsePosition();
    if (pos != null) {
      final place = await locationService.reverseGeocode(latitude: pos.latitude, longitude: pos.longitude);
      viewModel.updatePositionFromPipeline(lat: pos.latitude, lon: pos.longitude, placeLabel: place);
    }

    // 2) Get today photos
    final assets = await photoService.fetchTodayPhotos();
    if (assets.isEmpty) return;

    // 3) Choose up to N meaningful photos (event proximity + diversity)
    final events = await CalendarService().fetchTodayEventsLite().catchError((_) => <CalendarEventLite>[]);
    final eventTimes = events.map((e) => e.start).toList(growable: false);
    final selected = await photoService.chooseImportantSet(
      assets,
      maxCount: 3,
      eventTimes: eventTimes,
      minGap: const Duration(minutes: 90),
    );
    if (selected.isEmpty) return;

    // 4) For each photo, generate diary and store
    for (final asset in selected) {
      final Uint8List? bytes = await asset.originBytes;
      if (bytes == null) continue;
      final takenAt = await photoService.tryExtractExifDate(asset) ?? asset.createDateTime;
      await viewModel.generateFromAuto(bytes, takenAt);
    }
  }
}


