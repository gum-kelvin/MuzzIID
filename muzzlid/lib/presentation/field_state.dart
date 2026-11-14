import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/encrypted_register.dart';
import '../data/location_service.dart';
import '../domain/field_records.dart';
import '../domain/verification.dart';
import '../data/local_model.dart';
import 'state.dart';

final locationServiceProvider =
    Provider<LocationService>((ref) => DeviceLocationService());
final verificationServiceProvider = Provider<VerificationService>((ref) =>
    LocalModelVerification(ref.read(embeddingEngineProvider),
        () => ref.read(registerProvider.future)));
final embeddingEngineProvider =
    Provider<EmbeddingEngine>((ref) => AndroidEmbeddingEngine());
final modelStatusProvider = FutureProvider<Map<String, dynamic>>(
    (ref) => ref.read(embeddingEngineProvider).status());
final settingsProvider =
    AsyncNotifierProvider<SettingsController, Map<String, dynamic>>(
        SettingsController.new);

class SettingsController extends AsyncNotifier<Map<String, dynamic>> {
  final store = EncryptedSnapshot('settings.v1');
  Future<void> tail = Future.value();
  @override
  Future<Map<String, dynamic>> build() async {
    final rows = await store.read();
    return rows.isEmpty
        ? {'guided': true}
        : Map<String, dynamic>.from(rows.first);
  }

  Future<void> set(String key, dynamic value) {
    final result = tail.then((_) async {
      final next = {...await future, key: value};
      await store.save([next]);
      state = AsyncData(next);
    });
    tail = result.catchError((Object _) {});
    return result;
  }
}

final activityProvider =
    AsyncNotifierProvider<ActivityController, List<FieldActivity>>(
        ActivityController.new);

class ActivityController extends AsyncNotifier<List<FieldActivity>> {
  final store = EncryptedSnapshot('activities.v1');
  Future<void> tail = Future.value();
  @override
  Future<List<FieldActivity>> build() async => (await store.read())
      .map((j) => FieldActivity.fromJson(Map<String, dynamic>.from(j)))
      .toList();
  Future<void> settle(String id, String status) {
    final result = tail.then((_) async {
      final all = await future;
      final next = [
        for (final item in all)
          if (item.id == id)
            FieldActivity(
                id: item.id,
                kind: item.kind,
                animalId: item.animalId,
                time: item.time,
                gps: item.gps,
                frames: item.frames,
                status: status)
          else
            item
      ];
      await store.save(next.map((e) => e.toJson()).toList());
      state = AsyncData(next);
    });
    tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> add(FieldActivity item) {
    final result = tail.then((_) async {
      final all = [...await future, item];
      await store.save(all.map((e) => e.toJson()).toList());
      state = AsyncData(all);
    });
    tail = result.catchError((Object _) {});
    return result;
  }
}

final detectorStatusProvider = FutureProvider<bool>((ref) async =>
    (await AndroidEmbeddingEngine.channel
        .invokeMapMethod('detectorStatus'))?['ready'] ==
    true);
