import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzzlid/domain/register.dart';
import 'package:muzzlid/domain/field_records.dart';
import 'package:muzzlid/presentation/state.dart';

class PausedRepository implements RegisterRepository {
  List<Animal> animals = [];
  Completer<void>? started, release;
  @override
  Future<List<Animal>> read() async => [...animals];
  @override
  Future<void> save(List<Animal> records) async {
    final gate = release;
    if (gate != null) {
      release = null;
      started!.complete();
      await gate.future;
    }
    animals = [...records];
  }
}

Animal record(String id) => Animal(
    id: id,
    owner: 'Owner $id',
    district: 'Market',
    created: DateTime.utc(2026));
void main() {
  test('queued enrolments preserve both records', () async {
    final repo = PausedRepository();
    final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    await container.read(registerProvider.future);
    final controller = container.read(registerProvider.notifier);
    final gate = Completer<void>();
    repo.started = Completer();
    repo.release = gate;
    final save = controller.put(record('first'));
    await repo.started!.future;
    final second = controller.put(record('second'));
    gate.complete();
    await save;
    await second;
    expect(repo.animals.map((a) => a.id), ['first', 'second']);
    expect(repo.animals, hasLength(2));
  });
  test('queued vaccination and metadata changes preserve latest history',
      () async {
    final original = record('first'), repo = PausedRepository();
    repo.animals = [original];
    final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    await container.read(registerProvider.future);
    final controller = container.read(registerProvider.notifier);
    final gate = Completer<void>();
    repo.started = Completer();
    repo.release = gate;
    final one = controller.addVaccination(
        original,
        Vaccination(
            id: 'one', vaccine: 'FMD', administeredAt: DateTime.utc(2026)));
    await repo.started!.future;
    final two = controller.addVaccination(
        original,
        Vaccination(
            id: 'two', vaccine: 'Anthrax', administeredAt: DateTime.utc(2026)));
    final edit = controller.updateDetails(original,
        owner: 'Updated', location: 'New market', gps: null);
    gate.complete();
    await one;
    await two;
    await edit;
    expect(repo.animals.single.vaccinations, hasLength(2));
    expect(repo.animals.single.owner, 'Updated');
    expect(repo.animals.single.created, original.created);
  });
}
