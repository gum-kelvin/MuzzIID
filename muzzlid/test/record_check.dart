// ignore_for_file: avoid_relative_lib_imports, avoid_print
import '../lib/domain/register.dart';

void main() {
  final created = DateTime.utc(2026, 11, 14, 10, 30);
  final animal = Animal(
      id: 'receipt',
      owner: 'Owner',
      breed: 'Ankole',
      district: 'Mbarara market',
      created: created,
      vaccines: 'FMD · 2026-11-14');
  final json = animal.toJson();
  if (json.containsKey('nin') || json.containsKey('phone')) {
    throw StateError('New records must not emit NIN or phone');
  }
  final restored = Animal.fromJson(json);
  if (restored.location != 'Mbarara market' ||
      restored.created != created ||
      restored.vaccines != animal.vaccines) {
    throw StateError('Record round trip failed');
  }
  final legacy = Animal.fromJson({
    'id': 'old',
    'owner': 'Owner',
    'breed': 'Ankole',
    'district': 'Old location',
    'created': created.toIso8601String()
  });
  if (legacy.location != 'Old location' || legacy.vaccines.isNotEmpty) {
    throw StateError('Legacy migration failed');
  }
  print(
      'PASS: owner, UTC time, location and optional vaccine persistence; legacy records; no new NIN/phone');
}
