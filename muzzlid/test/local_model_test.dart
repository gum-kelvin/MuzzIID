import 'package:flutter_test/flutter_test.dart';
import 'package:muzzlid/data/local_model.dart';
import 'package:muzzlid/data/encrypted_register.dart';
import 'package:muzzlid/domain/register.dart';
import 'package:muzzlid/domain/field_records.dart';
import 'package:muzzlid/domain/verification.dart';

class MemoryTemplates extends EncryptedSnapshot {
  MemoryTemplates() : super('test');
  List<Map<String, dynamic>> data = [];
  @override
  Future<List<dynamic>> read() async => data;
  @override
  Future<void> save(List<Map<String, dynamic>> records) async {
    data = records;
  }
}

class Engine implements EmbeddingEngine {
  bool calibrated = true;
  String version = 'v1:hash';
  int calls = 0;
  @override
  Future<Map<String, dynamic>> status() async => {
        'ready': true,
        'calibrated': calibrated,
        'research': true,
        'version': version,
        'matchThreshold': .8,
        'uncertainThreshold': .6,
        'minimumMargin': .05
      };
  @override
  Future<List<double>> embed(String jpeg, String version) async {
    calls++;
    return List.generate(512, (i) => i == (jpeg == 'other' ? 1 : 0) ? 1 : 0);
  }
}

void main() {
  final gps = GeoFix(0, 32, 10, DateTime.now().toUtc());
  Animal animal(String id, String frame) => Animal(
      id: id,
      owner: 'Owner',
      district: '',
      created: DateTime.now().toUtc(),
      muzzleFrames: [frame]);
  test('calibration and incomplete local references fail to pending', () async {
    final engine = Engine()..calibrated = false;
    final service = LocalModelVerification(
        engine, () async => [animal('1', 'same')],
        templates: MemoryTemplates());
    expect(
        (await service.verify('same', gps)).status, VerificationStatus.pending);
    expect(engine.calls, 0);
    engine.calibrated = true;
    final empty = LocalModelVerification(engine, () async => [],
        templates: MemoryTemplates());
    expect(
        (await empty.verify('same', gps)).status, VerificationStatus.pending);
  });
  test('real matching, ambiguous neighbours and artifact isolation', () async {
    final engine = Engine();
    final cache = MemoryTemplates();
    var records = [animal('1', 'same')];
    final service =
        LocalModelVerification(engine, () async => records, templates: cache);
    final result = await service.verify('same', gps);
    expect(result.animal?.id, '1');
    expect(result.research, true);
    expect(engine.calls, 2);
    expect((await service.verify('other', gps)).status,
        VerificationStatus.unregistered);
    expect(engine.calls, 3); // Cached template, new query.
    engine.version = 'v2:new-hash';
    await service.verify('same', gps);
    expect(engine.calls, 5); // Different model rebuilds its reference.
    records = [...records, animal('2', 'same')];
    expect((await service.verify('same', gps)).status,
        VerificationStatus.uncertain);
  });
  test('invalid and zero embeddings rejected', () {
    expect(() => unitVector(List.filled(512, 0)), throwsFormatException);
    expect(() => unitVector([double.nan]), throwsFormatException);
  });
}
