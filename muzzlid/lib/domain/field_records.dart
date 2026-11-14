class GeoFix {
  final double latitude, longitude, accuracy;
  final DateTime capturedAt;
  const GeoFix(this.latitude, this.longitude, this.accuracy, this.capturedAt);
  String get label =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)} · ±${accuracy.round()} m';
  bool fresh(DateTime now) =>
      now.difference(capturedAt).abs() < const Duration(minutes: 5);
  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'capturedAt': capturedAt.toUtc().toIso8601String()
      };
  factory GeoFix.fromJson(Map<String, dynamic> j) {
    final lat = (j['latitude'] as num).toDouble(),
        lon = (j['longitude'] as num).toDouble(),
        accuracy = (j['accuracy'] as num).toDouble();
    if (!lat.isFinite ||
        !lon.isFinite ||
        !accuracy.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        accuracy < 0) {
      throw const FormatException('Invalid GPS');
    }
    return GeoFix(lat, lon, accuracy, DateTime.parse(j['capturedAt']));
  }
}

class Vaccination {
  final String id, vaccine, batch;
  final DateTime administeredAt;
  final DateTime? recordedAt;
  final DateTime? validUntil;
  final GeoFix? gps;
  const Vaccination(
      {required this.id,
      required this.vaccine,
      required this.administeredAt,
      this.recordedAt,
      this.validUntil,
      this.batch = '',
      this.gps});
  Map<String, dynamic> toJson() => {
        'id': id,
        'vaccine': vaccine,
        'administeredAt': administeredAt.toIso8601String(),
        'recordedAt': recordedAt?.toUtc().toIso8601String(),
        'validUntil': validUntil?.toIso8601String(),
        'batch': batch,
        'gps': gps?.toJson()
      };
  factory Vaccination.fromJson(Map<String, dynamic> j) {
    if ((j['id'] as String).isEmpty || (j['vaccine'] as String).isEmpty) {
      throw const FormatException('Invalid vaccination');
    }
    final date = DateTime.parse(j['administeredAt']),
        until =
            j['validUntil'] == null ? null : DateTime.parse(j['validUntil']);
    if (until != null && until.isBefore(date)) {
      throw const FormatException('Invalid validity dates');
    }
    return Vaccination(
        id: j['id'],
        vaccine: j['vaccine'],
        administeredAt: date,
        recordedAt:
            j['recordedAt'] == null ? null : DateTime.parse(j['recordedAt']),
        validUntil: until,
        batch: j['batch'] ?? '',
        gps: j['gps'] == null
            ? null
            : GeoFix.fromJson(Map<String, dynamic>.from(j['gps'])));
  }
}

class FieldActivity {
  final String id, kind, animalId;
  final DateTime time;
  final GeoFix? gps;
  final List<String> frames;
  final String status;
  const FieldActivity(
      {required this.id,
      required this.kind,
      required this.animalId,
      required this.time,
      this.gps,
      this.frames = const [],
      this.status = 'pending'});
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'animalId': animalId,
        'time': time.toUtc().toIso8601String(),
        'gps': gps?.toJson(),
        'frames': frames,
        'status': status
      };
  factory FieldActivity.fromJson(Map<String, dynamic> j) => FieldActivity(
      id: j['id'],
      kind: j['kind'],
      animalId: j['animalId'],
      time: DateTime.parse(j['time']),
      gps: j['gps'] == null
          ? null
          : GeoFix.fromJson(Map<String, dynamic>.from(j['gps'])),
      frames: List<String>.from(j['frames'] ?? []),
      status: j['status'] ?? 'pending');
}
