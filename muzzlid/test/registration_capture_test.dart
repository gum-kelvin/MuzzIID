import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzzlid/domain/registration_photos.dart';
import 'package:muzzlid/presentation/camera_geometry.dart';

void main() {
  test(
      'each accepted photo is distinct and freshly acquired; undo permits replacement',
      () {
    final shots = RegistrationPhotos();
    expect(shots.add('jpeg1', 1), true);
    expect(shots.add('jpeg1', 2), false);
    expect(shots.add('jpeg2', 1), false);
    expect(shots.count, 1);
    expect(shots.add('jpeg2', 3), true);
    shots.undo();
    expect(shots.count, 1);
    expect(shots.add('jpeg2', 4), true);
    for (var i = 3; i <= 5; i++) {
      expect(shots.add('jpeg$i', i + 3), true);
    }
    expect(shots.complete, true);
    expect(shots.add('extra', 20), false);
    expect(shots.photos, hasLength(5));
    expect(() => shots.photos.add('changed'), throwsUnsupportedError);
  });
  test(
      'cover preview fills screen and the capture ROI projects exactly to the guide',
      () {
    for (final size in [
      const Size(360, 640),
      const Size(411, 915),
      const Size(320, 568)
    ]) {
      for (final aspect in [2 / 3, 3 / 4]) {
        final layout = CameraGeometry(size, aspect);
        expect(layout.image.width, greaterThanOrEqualTo(size.width));
        expect(layout.image.height, greaterThanOrEqualTo(size.height));
        expect(layout.roi.left, greaterThanOrEqualTo(0));
        expect(layout.roi.top, greaterThanOrEqualTo(0));
        expect(layout.roi.right, lessThanOrEqualTo(1));
        expect(layout.roi.bottom, lessThanOrEqualTo(1));
        expect(layout.image.left + layout.image.width * layout.roi.left,
            closeTo(layout.guide.left, .001));
        expect(layout.image.top + layout.image.height * layout.roi.top,
            closeTo(layout.guide.top, .001));
        expect(layout.image.width * layout.roi.width,
            closeTo(layout.guide.width, .001));
      }
    }
  });
}
