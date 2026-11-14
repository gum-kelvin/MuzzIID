// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:typed_data';
import '../lib/domain/capture_policy.dart';
import '../lib/data/luma_analysis.dart';

void check(bool ok, String reason) {
  if (!ok) throw StateError(reason);
}

Future<void> main() async {
  const policy = CapturePolicy();
  CaptureIssue? gate({
    double sharp = 121,
    double light = 45,
    bool clean = true,
    CaptureRect muzzle = const CaptureRect(10, 10, 80, 50),
    bool occluded = false,
  }) =>
      policy.evaluate(
        CaptureMetrics(
          sharpness: sharp,
          luminance: light,
          muzzle: muzzle,
          reticle: const CaptureRect(0, 0, 100, 100),
          safeFrame: const CaptureRect(0, 0, 100, 100),
          occluded: occluded,
        ),
        hygieneConfirmed: clean,
      );
  check(gate() == null, '40% occupancy and luminance 45 must pass');
  check(gate(light: 215) == null, '215 inclusive');
  check(gate(sharp: 120) == CaptureIssue.blur, '120 must fail');
  check(gate(light: 44) == CaptureIssue.dark, 'Underexposure');
  check(gate(light: 216) == CaptureIssue.glare, 'Overexposure');
  check(gate(clean: false) == CaptureIssue.hygiene, 'Hygiene mandatory');
  check(gate(occluded: true) == CaptureIssue.occlusion, 'Occlusion blocks');
  check(gate(sharp: double.nan) == CaptureIssue.invalid, 'NaN blocks');
  check(
    gate(muzzle: const CaptureRect(-1, 0, 80, 80)) == CaptureIssue.framing,
    'Corners inside',
  );
  check(
    gate(muzzle: const CaptureRect(0, 0, 10, 10)) == CaptureIssue.distance,
    'Scale gate',
  );
  final burst = EnrolmentBurst();
  for (final stamp in [0, 375, 750, 1125, 1500]) {
    burst.accept(timestampMs: stamp, valid: true);
  }
  check(burst.complete, 'Five frames over 1.5 seconds');
  burst.reset();
  burst.accept(timestampMs: 0, valid: true);
  burst.accept(timestampMs: 100, valid: false);
  check(burst.count == 0, 'Invalid intermediate frame resets');
  burst.accept(timestampMs: 200, valid: true);
  burst.accept(timestampMs: 900, valid: true);
  check(burst.count == 1, 'Stalled source resets');
  burst.accept(timestampMs: 899, valid: true);
  check(burst.count == 0, 'Out of order resets');
  final flat = await analyseLuma(
    Uint8List.fromList(List.filled(25, 100)),
    width: 5,
    height: 5,
    rowStride: 5,
  );
  check(
    flat.mean == 100 && flat.laplacianVariance == 0,
    'Flat ROI must be blurry',
  );
  final texture = await analyseLuma(
    Uint8List.fromList(List.generate(25, (i) => i.isEven ? 200 : 50)),
    width: 5,
    height: 5,
    rowStride: 5,
  );
  check(texture.laplacianVariance > 120, 'Textured ROI has focus signal');
  print(
    'PASS: quality boundaries, hygiene, geometry, burst reset/timing, isolate luma analysis',
  );
}
