import 'package:flutter_test/flutter_test.dart';
import 'package:muzzlid/presentation/luganda_material.dart';

void main() {
  test('Luganda calendar formats and validates day/month dates', () {
    const locale = LugandaMaterial();
    expect(locale.cancelButtonLabel, 'Sazaamu');
    expect(locale.formatMonthYear(DateTime(2026, 11)), 'Novemba 2026');
    expect(locale.parseCompactDate('14/11/2026'), DateTime(2026, 11, 14));
    expect(locale.parseCompactDate('31/02/2026'), isNull);
  });
}
