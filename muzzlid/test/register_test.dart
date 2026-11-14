import 'package:flutter_test/flutter_test.dart';
import 'package:muzzlid/domain/register.dart';

void main() {
  test('three-way open-set boundaries', () {
    MatchStatus check(double score) =>
        classify(score, model: 'v1', templateModel: 'v1');
    expect(check(.78), MatchStatus.confirmed);
    expect(check(.68), MatchStatus.ambiguous);
    expect(check(.679), MatchStatus.unknown);
    expect(() => check(double.nan), throwsArgumentError);
  });
  test('incompatible embeddings cannot be compared', () {
    expect(
      () => classify(.99, model: 'v2', templateModel: 'v1'),
      throwsArgumentError,
    );
  });
  test('malformed imports fail validation', () {
    expect(() => Animal.fromJson({'id': 'a'}), throwsFormatException);
  });
}
