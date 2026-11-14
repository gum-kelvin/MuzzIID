import 'field_records.dart';
import 'dart:convert';

class Animal {
  final String id, owner, breed, district;
  final DateTime created;
  final GeoFix? gps;
  final List<Vaccination> vaccinations;
  final String syncState, syncError;
  String get location => district; // Legacy storage/API name remains readable.
  final String nin, phone, receiptId, vaccines;
  final List<String> muzzleFrames;
  const Animal({
    required this.id,
    required this.owner,
    this.breed = '',
    this.gps,
    this.vaccinations = const [],
    this.syncState = 'pending',
    this.syncError = '',
    required this.district,
    required this.created,
    this.vaccines = '',
    this.nin = '',
    this.phone = '',
    this.receiptId = '',
    this.muzzleFrames = const [],
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'owner': owner,
        if (breed.isNotEmpty) 'breed': breed,
        'gps': gps?.toJson(),
        'vaccinations': vaccinations.map((v) => v.toJson()).toList(),
        'syncState': syncState, 'syncError': syncError,
        'location': location,
        'created': created.toUtc().toIso8601String(),
        // Retain legacy fields only when an older record already has them.
        if (nin.isNotEmpty) 'nin': nin,
        if (phone.isNotEmpty) 'phone': phone,
        'vaccines': vaccines,
        'receiptId': receiptId,
        'muzzleFrames': muzzleFrames,
      };
  Animal copyWith(
          {String? owner,
          String? district,
          GeoFix? gps,
          List<Vaccination>? vaccinations,
          String? syncState,
          String? syncError}) =>
      Animal(
          id: id,
          owner: owner ?? this.owner,
          breed: breed,
          district: district ?? this.district,
          created: created,
          nin: nin,
          phone: phone,
          receiptId: receiptId,
          vaccines: vaccines,
          muzzleFrames: muzzleFrames,
          gps: gps ?? this.gps,
          vaccinations: vaccinations ?? this.vaccinations,
          syncState: syncState ?? this.syncState,
          syncError: syncError ?? this.syncError);

  factory Animal.fromJson(Map<String, dynamic> j) {
    j = {...j, 'district': j['location'] ?? j['district']};
    for (final key in ['id', 'owner', 'created']) {
      if (j[key] is! String || (j[key] as String).trim().isEmpty) {
        throw const FormatException('Invalid animal record');
      }
    }
    final frames = List<String>.from(j['muzzleFrames'] as List? ?? const []);
    if (frames.length > 5) {
      throw const FormatException('Too many muzzle frames');
    }
    for (final frame in frames) {
      final bytes = base64Decode(frame);
      if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
        throw const FormatException('Invalid muzzle JPEG');
      }
    }
    return Animal(
      id: j['id'],
      owner: j['owner'],
      breed: j['breed'] as String? ?? '',
      district: j['district'] as String? ?? '',
      gps: j['gps'] == null
          ? null
          : GeoFix.fromJson(Map<String, dynamic>.from(j['gps'])),
      vaccinations: (j['vaccinations'] as List? ?? [])
          .map((v) => Vaccination.fromJson(Map<String, dynamic>.from(v)))
          .toList(),
      syncState: j['syncState'] as String? ?? 'pending',
      syncError: j['syncError'] as String? ?? '',
      created: DateTime.parse(j['created']),
      vaccines: j['vaccines'] as String? ?? '',
      nin: j['nin'] as String? ?? '',
      phone: j['phone'] as String? ?? '',
      receiptId: j['receiptId'] as String? ?? '',
      muzzleFrames: List.unmodifiable(frames),
    );
  }
}

abstract interface class RegisterRepository {
  Future<List<Animal>> read();
  Future<void> save(List<Animal> animals);
}

class RegisterUseCases {
  final RegisterRepository repository;
  RegisterUseCases(this.repository);
  Future<void> upsert(Animal animal) async {
    final all = await repository.read();
    final index = all.indexWhere((a) => a.id == animal.id);
    if (index < 0) {
      all.add(animal);
    } else {
      all[index] = animal;
    }
    await repository.save(all);
  }

  Future<void> delete(String id) async => repository.save(
        (await repository.read()).where((a) => a.id != id).toList(),
      );
}

enum MatchStatus { confirmed, ambiguous, unknown }

MatchStatus classify(
  double score, {
  required String model,
  required String templateModel,
}) {
  if (model != templateModel || !score.isFinite || score < -1 || score > 1) {
    throw ArgumentError('Incompatible model or invalid score');
  }
  return score >= .78
      ? MatchStatus.confirmed
      : score >= .68
          ? MatchStatus.ambiguous
          : MatchStatus.unknown;
}
