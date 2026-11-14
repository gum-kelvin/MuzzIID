import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muzzlid/data/local_model.dart';
import 'package:muzzlid/data/encrypted_register.dart';
import 'package:muzzlid/domain/register.dart';
import 'package:muzzlid/domain/field_records.dart';
import 'package:muzzlid/domain/verification.dart';
import 'model_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bundled research ONNX enrolment centroid and open-set decisions',
      (tester) async {
    final engine = AndroidEmbeddingEngine();
    final info = await engine.status();
    expect(info['ready'], true);
    expect(info['version'], baselineFixtureVersion,
        reason:
            'Regenerate smoke fixtures when replacing the bundled baseline.');
    final store = EncryptedSnapshot('android-model-test.v1');
    await store.save([]);
    try {
      final animal = Animal(
          id: 'MODEL-SMOKE-ONLY',
          owner: 'Dataset fixture',
          district: '',
          created: DateTime.now().toUtc(),
          muzzleFrames: baselineGallery);
      final service = LocalModelVerification(engine, () async => [animal],
          templates: store);
      final gps = GeoFix(0, 32, 10, DateTime.now().toUtc());
      final same = await service.verify(baselineProbe, gps);
      expect(same.status, VerificationStatus.verified);
      expect(same.animal?.id, animal.id);
      expect(same.research, true);
      final different = await service.verify(baselineUnknown, gps);
      expect(different.status, VerificationStatus.unregistered);
      expect((await store.read()).single['version'], baselineFixtureVersion);
      // Reuse the encrypted centroid on a second query, preserving model isolation.
      expect((await service.verify(baselineProbe, gps)).status,
          VerificationStatus.verified);
      expect(tester.takeException(), isNull);
      // No production register records are created by this test.
    } finally {
      await store.save([]);
    }
  });
}
