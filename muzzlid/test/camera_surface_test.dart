import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzzlid/presentation/scanner_view.dart';
import 'package:muzzlid/presentation/camera_geometry.dart';
import 'package:muzzlid/presentation/state.dart';
import 'package:muzzlid/presentation/receipt_screen.dart';
import 'package:muzzlid/domain/register.dart';
import 'package:muzzlid/domain/field_records.dart';

Widget host(Widget child) => ProviderScope(overrides: [
      languageProvider.overrideWith((ref) => LanguageController(persist: false))
    ], child: MaterialApp(home: Scaffold(body: child)));
void main() {
  testWidgets('camera has no acknowledgement gates and one shutter event',
      (tester) async {
    var presses = 0;
    await tester.pumpWidget(host(ScannerView(
        camera: null,
        geometry: CameraGeometry(const Size(800, 600), 3 / 4),
        registration: true,
        ready: true,
        busy: false,
        detector: false,
        photos: const [],
        instruction: 'Ready to capture',
        onCapture: () => presses++,
        onRetry: () {},
        onBack: () {})));
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Photos 0 / 5'), findsOneWidget);
    expect(find.text('Take five photos of the same muzzle.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('capture-photo')));
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('receipt never renders automatic coordinates or audit time',
      (tester) async {
    final animal = Animal(
        id: 'local-test',
        owner: 'Owner',
        district: 'Market',
        created: DateTime.utc(2026, 11, 14, 12, 34),
        gps: GeoFix(.12345, 32.54321, 8, DateTime.utc(2026, 11, 14, 12, 34)));
    await tester.pumpWidget(host(ReceiptScreen(animal: animal)));
    expect(find.textContaining('0.12345'), findsNothing);
    expect(find.textContaining('32.54321'), findsNothing);
    expect(find.textContaining('12:34'), findsNothing);
    expect(find.text('Recorded'), findsNothing);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Register another'), findsOneWidget);
  });
}
