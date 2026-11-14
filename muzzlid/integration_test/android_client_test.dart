import 'dart:io';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:muzzlid/data/encrypted_register.dart';
import 'package:muzzlid/data/location_service.dart';
import 'package:muzzlid/domain/register.dart';
import 'package:muzzlid/domain/field_records.dart';
import 'package:muzzlid/main.dart';
import 'package:muzzlid/presentation/state.dart';
import 'package:muzzlid/presentation/field_state.dart';
import 'package:muzzlid/presentation/registration_screen.dart';
import 'package:muzzlid/presentation/profile_screen.dart';
import 'package:muzzlid/presentation/vaccination_screen.dart';

class TestLocation implements LocationService {
  @override
  Future<GeoFix> locate() async =>
      GeoFix(-.607, 30.654, 8, DateTime.now().toUtc());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
      'Android encrypted wizard, receipt, profile, vaccination and Luganda',
      (tester) async {
    final filename = 'android-test-${DateTime.now().microsecondsSinceEpoch}.v1';
    final repository = EncryptedRegister(filename: filename);
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/$filename');
    addTearDown(() async {
      if (await file.exists()) await file.delete();
      await const FlutterSecureStorage().delete(key: 'key-$filename');
    });
    final fixture = Animal(
        id: 'TEST-ANDROID',
        owner: 'Private Test Owner',
        district: 'Mbarara',
        created: DateTime.utc(2026));
    await repository.save([fixture]);
    expect(
        utf8
            .decode(await file.readAsBytes(), allowMalformed: true)
            .contains(fixture.owner),
        false);
    expect((await EncryptedRegister(filename: filename).read()).single.owner,
        fixture.owner);
    // A missing platform key must fail closed without rewriting encrypted data,
    // and retry must recover once that same key becomes available again.
    const vault = FlutterSecureStorage();
    final keyName = 'key-$filename';
    final originalKey = await vault.read(key: keyName);
    final ciphertext = await file.readAsBytes();
    await vault.delete(key: keyName);
    final retryRepository = EncryptedRegister(filename: filename);
    await expectLater(retryRepository.read(), throwsStateError);
    expect(await file.readAsBytes(), ciphertext);
    await vault.write(key: keyName, value: originalKey);
    expect((await retryRepository.read()).single.owner, fixture.owner);
    await repository.save([]);
    await tester.pumpWidget(ProviderScope(overrides: [
      languageProvider
          .overrideWith((ref) => LanguageController(persist: false)),
      repositoryProvider.overrideWithValue(repository),
      locationServiceProvider.overrideWithValue(TestLocation()),
      // This test exercises the workflow; camera-frame analysis is tested separately.
      captureFramesProvider.overrideWithValue((context) async => List.generate(
          5,
          (index) => base64Encode(img.encodeJpg(img.fill(
              img.Image(width: 8, height: 8),
              color: img.ColorRgb8(index * 45, 120, 80)))))),
    ], child: const MuzzlidApp()));
    await tester.pumpAndSettle();
    final screenshots = Directory('${directory.path}/ui-test-screenshots');
    await screenshots.create(recursive: true);
    await binding.convertFlutterSurfaceToImage();
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await File('${screenshots.path}/$name.png')
          .writeAsBytes(await binding.takeScreenshot(name));
    }

    expect(find.text('MuzzlID', findRichText: true), findsOneWidget);
    await shot('field');
    expect(find.text('Saved offline'), findsNothing);
    expect(find.text('District manifest'), findsNothing);
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register animal'));
    await tester.pumpAndSettle();
    Finder scrollOf(Type type) => find
        .descendant(of: find.byType(type), matching: find.byType(Scrollable))
        .first;
    Future<void> tapVisible(String text, Type screen) async {
      await tester.scrollUntilVisible(find.text(text), 140,
          scrollable: scrollOf(screen));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    await tester.enterText(
        find.byKey(const ValueKey('Owner name')), 'Private Test Owner');
    await tester.enterText(
        find.byKey(const ValueKey('Place label')), 'Mbarara market');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapVisible('Next: capture muzzle', RegistrationScreen);
    expect(find.text('Vaccination & review'), findsOneWidget);
    await shot('registration-review');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FMD'));
    await tester.pumpAndSettle();
    await tapVisible('Save registration', RegistrationScreen);
    expect(find.text('Receipt'), findsOneWidget);
    await shot('receipt');
    final saved = (await repository.read()).single;
    expect(saved.muzzleFrames, hasLength(5));
    expect(saved.gps!.latitude, -.607);
    expect(saved.breed, isEmpty);
    expect(saved.vaccinations.single.vaccine, 'FMD');
    expect(saved.created.isUtc, true);
    final receiptScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Back to Field'), 160,
        scrollable: receiptScroll);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to Field'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pumpAndSettle();
    await shot('register');
    await tester.tap(find.text(saved.id));
    await tester.pumpAndSettle();
    await shot('profile');
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit animal'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('Owner name')), 'Updated Owner');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapVisible('Save changes', RegistrationScreen);
    expect((await repository.read()).single.owner, 'Updated Owner');
    expect((await repository.read()).single.created, saved.created);
    await tapVisible('Add vaccination', AnimalProfileScreen);
    await tester.tap(find.text('Anthrax'));
    await tester.pumpAndSettle();
    await tapVisible('Save vaccination', VaccinationScreen);
    expect((await repository.read()).single.vaccinations, hasLength(2));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await repository.read(), isEmpty);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Saved offline'), findsOneWidget);
    for (final removed in [
      'Export & import',
      'About',
      'Haptic feedback',
      'High-contrast outdoor theme',
      'District manifest'
    ]) {
      expect(find.text(removed), findsNothing);
    }
    await tester.scrollUntilVisible(find.byType(SegmentedButton<String>), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luganda').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Olulimi'), findsOneWidget);
    await shot('settings-luganda');
    expect(tester.takeException(), isNull);
  });
}
