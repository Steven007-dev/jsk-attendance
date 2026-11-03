import 'package:geolocator/geolocator.dart';

class LocationCheckResult {
  const LocationCheckResult({this.distanceMeters, this.error});
  final double? distanceMeters;
  final String? error;
  bool get accepted => error == null && distanceMeters != null;
}

class InstituteLocationService {
  Future<LocationCheckResult> checkInside({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationCheckResult(
          error: 'Turn on location services to check in.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationCheckResult(
          error: 'Location permission is required for staff attendance.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        latitude,
        longitude,
      );
      if (distance > radiusMeters) {
        return LocationCheckResult(
          distanceMeters: distance,
          error:
              'You are ${distance.round()} m away. You must be within ${radiusMeters.round()} m of the institute.',
        );
      }
      return LocationCheckResult(distanceMeters: distance);
    } catch (error) {
      return LocationCheckResult(error: 'Could not get your location: $error');
    }
  }
}
