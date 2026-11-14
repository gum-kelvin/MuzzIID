import 'package:geolocator_android/geolocator_android.dart';
import '../domain/field_records.dart';

abstract interface class LocationService {
  Future<GeoFix> locate();
}

class DeviceLocationService implements LocationService {
  final device = GeolocatorAndroid();
  @override
  Future<GeoFix> locate() async {
    if (!await device.isLocationServiceEnabled()) {
      throw StateError('Turn on GPS in Android settings.');
    }
    var permission = await device.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await device.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Allow location access in Android settings.');
    }
    final p = await device.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)));
    return GeoFix(p.latitude, p.longitude, p.accuracy, p.timestamp.toUtc());
  }
}
