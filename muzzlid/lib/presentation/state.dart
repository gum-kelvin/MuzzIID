import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/encrypted_register.dart';
import '../domain/register.dart';
import '../domain/field_records.dart';

final languageProvider = StateNotifierProvider<LanguageController, String>(
    (ref) => LanguageController());

class LanguageController extends StateNotifier<String> {
  LanguageController({this.persist = true}) : super('en') {
    if (persist) _load();
  }
  final bool persist;
  bool changed = false;
  final vault = const FlutterSecureStorage();
  Future<void> _load() async {
    try {
      final saved = await vault.read(key: 'ui-language');
      if (mounted && !changed && ['en', 'lg'].contains(saved)) state = saved!;
    } catch (_) {/* Retain English when preference storage is unavailable. */}
  }

  Future<void> select(String language) async {
    if (!['en', 'lg'].contains(language)) return;
    changed = true;
    state = language;
    if (!persist) return;
    try {
      await vault.write(key: 'ui-language', value: language);
    } catch (_) {/* Session selection still applies. */}
  }
}

final repositoryProvider = Provider<RegisterRepository>(
  (ref) => EncryptedRegister(),
);
final registerProvider =
    AsyncNotifierProvider<RegisterController, List<Animal>>(
  RegisterController.new,
);

class RegisterController extends AsyncNotifier<List<Animal>> {
  @override
  Future<List<Animal>> build() => ref.read(repositoryProvider).read();
  Future<void> _tail = Future<void>.value();

  Future<void> _mutate(List<Animal> Function(List<Animal>) change) {
    final next = _tail.then((_) async {
      final animals = change([...state.requireValue]);
      await ref.read(repositoryProvider).save(animals);
      state = AsyncData(animals);
    });
    // A failed write must not poison later operations.
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> replace(List<Animal> animals) => _mutate((_) => [...animals]);
  Future<void> put(Animal animal) => _mutate((all) {
        final index = all.indexWhere((a) => a.id == animal.id);
        if (index < 0) {
          all.add(animal);
        } else {
          all[index] = animal;
        }
        return all;
      });
  Future<void> updateDetails(Animal reference,
          {required String owner,
          required String location,
          required GeoFix? gps}) =>
      _update(
          reference,
          (current) => current.copyWith(
              owner: owner,
              district: location,
              gps: gps,
              syncState: 'pending',
              syncError: ''));
  Future<void> addVaccination(Animal reference, Vaccination dose) =>
      _update(reference, (current) {
        if (current.vaccinations.any((v) => v.id == dose.id)) return current;
        return current.copyWith(
            vaccinations: [...current.vaccinations, dose],
            syncState: 'pending',
            syncError: '');
      });
  Future<void> _update(Animal reference, Animal Function(Animal) change) =>
      _mutate((all) {
        final index = all.indexWhere((a) => a.id == reference.id);
        final updated = change(index < 0 ? reference : all[index]);
        if (index < 0) {
          all.add(updated);
        } else {
          all[index] = updated;
        }
        return all;
      });
  Future<void> remove(String id) =>
      _mutate((all) => all.where((a) => a.id != id).toList());
}

final shellTabProvider = StateProvider<int>((ref) => 0);
