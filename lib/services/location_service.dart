import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  const LocationService();

  Future<bool> _ensurePermission() async {
    // Check and request location permission (When In Use)
    PermissionStatus status = await Permission.locationWhenInUse.status;
    if (status.isDenied || status.isRestricted) {
      status = await Permission.locationWhenInUse.request();
    }
    return status.isGranted;
  }

  Future<Position?> getCurrentPosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    final bool granted = await _ensurePermission();
    if (!granted) {
      return null;
    }

    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<String?> reverseGeocode({required double latitude, required double longitude}) async {
    try {
      final List<geocoding.Placemark> placemarks =
          await geocoding.placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final geocoding.Placemark p = placemarks.first;
      final List<String> parts = [
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
        if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!.trim(),
        if ((p.administrativeArea ?? '').trim().isNotEmpty) p.administrativeArea!.trim(),
      ];
      if (parts.isEmpty) {
        // Fallback to country
        final String? country = p.country?.trim();
        return (country == null || country.isEmpty) ? null : country;
      }
      return parts.join(' ');
    } catch (_) {
      return null;
    }
  }

  // Passive logging could be implemented using periodic fetch at coarse accuracy
  Future<Position?> getCoarsePosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    final bool granted = await _ensurePermission();
    if (!granted) return null;
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
  }
}



