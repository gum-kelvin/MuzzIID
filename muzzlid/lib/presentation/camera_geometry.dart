import 'dart:math' as math;
import 'dart:ui';

/// Projects the on-screen guide back into the full sensor image after cover-fit.
/// Capture and detector inputs use exactly the region the operator can see.
class CameraGeometry {
  final Rect image, guide, roi;
  CameraGeometry._(this.image, this.guide, this.roi);
  factory CameraGeometry(Size viewport, double uprightAspect) {
    final height = math.max(viewport.height, viewport.width / uprightAspect);
    final width = height * uprightAspect;
    final image = Rect.fromLTWH((viewport.width - width) / 2,
        (viewport.height - height) / 2, width, height);
    final side = math.min(viewport.width * .78,
        math.min(viewport.height * .36, math.max(96.0, viewport.height - 450)));
    final centerY =
        math.min(viewport.height * .53, viewport.height - 240 - side / 2);
    final guide = Rect.fromLTWH((viewport.width - side) / 2,
        math.max(100.0, centerY - side / 2), side, side);
    final roi = Rect.fromLTWH(
        (guide.left - image.left) / image.width,
        (guide.top - image.top) / image.height,
        guide.width / image.width,
        guide.height / image.height);
    return CameraGeometry._(image, guide, roi);
  }
}
