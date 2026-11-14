// ignore_for_file: avoid_relative_lib_imports, avoid_print
import '../lib/domain/field_records.dart';
import '../lib/domain/register.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final now = DateTime.utc(2026, 11, 14, 10);
  final gps = GeoFix(-.607, 30.654, 8, now);
  final dose = Vaccination(
      id: 'v1',
      vaccine: 'FMD',
      administeredAt: now,
      gps: gps,
      validUntil: DateTime.utc(2027),
      batch: 'FMD-1');
  final animal = Animal(
      id: 'local1',
      owner: 'Owner',
      district: 'Market',
      created: now,
      gps: gps,
      vaccinations: [dose]);
  final restored = Animal.fromJson(animal.toJson());
  check(restored.breed.isEmpty, 'Breed must be optional');
  check(
      !animal.toJson().containsKey('breed'), 'New records must not emit breed');
  check(restored.gps!.accuracy == 8, 'GPS accuracy round trip');
  check(restored.vaccinations.single.batch == 'FMD-1',
      'Structured vaccination persistence');
  final updated = restored.copyWith(
      owner: 'Updated',
      vaccinations: [
        ...restored.vaccinations,
        Vaccination(id: 'v2', vaccine: 'Anthrax', administeredAt: now)
      ],
      syncState: 'pending');
  check(
      updated.vaccinations.length == 2 &&
          updated.created == now &&
          updated.gps!.latitude == gps.latitude,
      'Edit must preserve history and original capture metadata');
  check(!gps.fresh(now.add(const Duration(minutes: 6))),
      'Stale GPS must be refreshed');
  var rejected = false;
  try {
    GeoFix.fromJson({...gps.toJson(), 'latitude': 100});
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'Invalid coordinate rejection');
  rejected = false;
  try {
    Vaccination.fromJson(
        {...dose.toJson(), 'validUntil': DateTime.utc(2025).toIso8601String()});
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'Invalid vaccine dates must be rejected');
  final scan = FieldActivity(
      id: 'scan1',
      kind: 'Verification',
      animalId: '',
      time: now,
      gps: gps,
      frames: ['encrypted-at-rest-payload']);
  check(FieldActivity.fromJson(scan.toJson()).status == 'pending',
      'Deferred verification must remain pending');
  print(
      'PASS: GPS freshness/ranges, structured vaccine/date validation, profile edits, pending scan persistence, breed removal');
}
