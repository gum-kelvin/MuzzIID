import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzzlid/domain/register.dart';
import 'package:muzzlid/domain/field_records.dart';
import 'package:muzzlid/presentation/register_view.dart';
import 'package:muzzlid/presentation/state.dart';
import 'package:muzzlid/presentation/ui_parts.dart';

Widget host(Widget child) => ProviderScope(overrides: [
      languageProvider.overrideWith((ref) => LanguageController(persist: false))
    ], child: MaterialApp(home: Scaffold(body: child)));
void main() {
  testWidgets('large registers only build visible rows', (tester) async {
    await tester.pumpWidget(host(RegisterView(animals: [
      for (var i = 0; i < 1000; i++)
        Animal(
            id: 'id$i',
            owner: 'Owner',
            district: 'Market',
            created: DateTime.utc(2026))
    ])));
    expect(find.byType(ListTile).evaluate().length, lessThan(20));
    expect(tester.takeException(), isNull);
  });
  testWidgets('location errors stay actionable without exposing coordinates',
      (tester) async {
    const message = 'Turn on GPS in Android settings.';
    await tester.pumpWidget(host(GpsSummary(
        fix: GeoFix(0, 30, 8, DateTime.utc(2026)),
        error: message,
        onRetry: () {})));
    expect(find.text(message), findsOneWidget);
    expect(find.textContaining('30.00000'), findsNothing);
    expect(find.text('GPS location'), findsNothing);
  });
  testWidgets('malformed thumbnail cannot break a screen', (tester) async {
    await tester.pumpWidget(host(animalPhoto(Animal(
        id: 'a',
        owner: 'Owner',
        district: '',
        created: DateTime.utc(2026),
        muzzleFrames: const ['%%%']))));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
