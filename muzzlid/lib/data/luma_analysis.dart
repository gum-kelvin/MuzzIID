import 'dart:isolate';
import 'dart:typed_data';

class LumaStatistics {
  final double mean, laplacianVariance;
  const LumaStatistics(this.mean, this.laplacianVariance);
}

/// Analyses a cropped Y plane. The adapter supplies row/pixel strides; padding
/// is excluded. Native OpenCV parity and camera-device benchmarks are pending.
Future<LumaStatistics> analyseLuma(
  Uint8List bytes, {
  required int width,
  required int height,
  required int rowStride,
  int pixelStride = 1,
}) async {
  if (width < 3 ||
      height < 3 ||
      pixelStride < 1 ||
      rowStride < (width - 1) * pixelStride + 1 ||
      bytes.length < (height - 1) * rowStride + (width - 1) * pixelStride + 1) {
    throw ArgumentError('Invalid Y-plane geometry');
  }
  // Copy ownership before scheduling to prevent reused camera buffers changing.
  final plane = Uint8List.fromList(bytes);
  return Isolate.run(() {
    int at(int x, int y) => plane[y * rowStride + x * pixelStride];
    double sum = 0, lapSum = 0, squares = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        sum += at(x, y);
        if (x > 0 && y > 0 && x < width - 1 && y < height - 1) {
          final lap = at(x - 1, y) +
              at(x + 1, y) +
              at(x, y - 1) +
              at(x, y + 1) -
              4 * at(x, y);
          lapSum += lap;
          squares += lap * lap;
        }
      }
    }
    final n = (width - 2) * (height - 2);
    final average = lapSum / n;
    final variance = squares / n - average * average;
    return LumaStatistics(sum / (width * height), variance < 0 ? 0 : variance);
  });
}
