/// Specification §2 stage 1. Coordinates are in the same image space.
class CaptureRect {
  final double left, top, width, height;
  const CaptureRect(this.left, this.top, this.width, this.height);
  bool get valid =>
      [left, top, width, height].every((v) => v.isFinite) &&
      width > 0 &&
      height > 0;
  double get area => width * height;
  bool contains(CaptureRect r) =>
      valid &&
      r.valid &&
      r.left >= left &&
      r.top >= top &&
      r.left + r.width <= left + width &&
      r.top + r.height <= top + height;
}

class CaptureMetrics {
  final double sharpness, luminance;
  final CaptureRect muzzle, reticle, safeFrame;
  final bool occluded;
  const CaptureMetrics({
    required this.sharpness,
    required this.luminance,
    required this.muzzle,
    required this.reticle,
    required this.safeFrame,
    this.occluded = false,
  });
}

enum CaptureIssue {
  hygiene,
  invalid,
  occlusion,
  framing,
  distance,
  blur,
  dark,
  glare,
}

/// Shared by live camera gating and full detector/framing policy.
CaptureIssue? qualityIssue(double sharpness, double luminance) {
  if (!sharpness.isFinite ||
      sharpness < 0 ||
      !luminance.isFinite ||
      luminance < 0 ||
      luminance > 255) {
    return CaptureIssue.invalid;
  }
  if (sharpness <= 120) return CaptureIssue.blur;
  if (luminance < 45) return CaptureIssue.dark;
  if (luminance > 215) return CaptureIssue.glare;
  return null;
}

class CapturePolicy {
  const CapturePolicy();
  CaptureIssue? evaluate(CaptureMetrics m, {required bool hygieneConfirmed}) {
    if (!hygieneConfirmed) return CaptureIssue.hygiene;
    if (!m.sharpness.isFinite ||
        m.sharpness < 0 ||
        !m.luminance.isFinite ||
        m.luminance < 0 ||
        m.luminance > 255 ||
        !m.muzzle.valid ||
        !m.reticle.valid ||
        !m.safeFrame.valid) {
      return CaptureIssue.invalid;
    }
    if (m.occluded) return CaptureIssue.occlusion;
    if (!m.safeFrame.contains(m.muzzle) || !m.reticle.contains(m.muzzle)) {
      return CaptureIssue.framing;
    }
    if (m.muzzle.area / m.reticle.area < .4) return CaptureIssue.distance;
    return qualityIssue(m.sharpness, m.luminance);
  }
}

/// Samples five valid frames over 1.5 seconds. The source must submit every
/// analysed frame: invalid frames reset the burst even between sampling times.
/// Timestamps are monotonic camera timestamps, never wall-clock time.
class RegistrationBurst {
  final List<int> _times = [];
  int? _lastFrame;
  int get count => _times.length;
  bool get complete => count == 5;
  int get durationMs => _times.length < 2 ? 0 : _times.last - _times.first;
  void reset() {
    _times.clear();
    _lastFrame = null;
  }

  bool accept({required int timestampMs, required bool valid}) {
    if (complete) return true;
    if (!valid ||
        timestampMs < 0 ||
        (_lastFrame != null && timestampMs <= _lastFrame!)) {
      reset();
      return false;
    }
    if (_lastFrame != null && timestampMs - _lastFrame! > 500) _times.clear();
    _lastFrame = timestampMs;
    if (_times.isEmpty || timestampMs - _times.last >= 375) {
      _times.add(timestampMs);
    }
    return complete;
  }
}
