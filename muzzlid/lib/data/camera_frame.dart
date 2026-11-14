import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;

/// Rotation-aware guided ROI. Plane strides are bound once per frame rather
/// than looked up through dynamic maps for every pixel. Called in an isolate.
Map<String, dynamic> processCameraFrame(Map<String, dynamic> input) {
  final width = input['width'] as int, height = input['height'] as int;
  final rotation = input['rotation'] as int, planes = input['planes'] as List;
  if (width < 8 ||
      height < 8 ||
      ![0, 90, 180, 270].contains(rotation) ||
      planes.length < 3) {
    throw ArgumentError('Invalid YUV frame');
  }
  final yp = planes[0] as Map, up = planes[1] as Map, vp = planes[2] as Map;
  final yBytes = yp['bytes'] as Uint8List,
      uBytes = up['bytes'] as Uint8List,
      vBytes = vp['bytes'] as Uint8List;
  final yRow = yp['row'] as int,
      yPixel = yp['pixel'] as int,
      uRow = up['row'] as int,
      uPixel = up['pixel'] as int,
      vRow = vp['row'] as int,
      vPixel = vp['pixel'] as int;
  final uprightWidth = rotation % 180 == 0 ? width : height,
      uprightHeight = rotation % 180 == 0 ? height : width;
  final left = (uprightWidth * .125).round(),
      top = (uprightHeight * .4).round();
  final w = (uprightWidth * .75).round(), h = (uprightHeight * .45).round();
  // Source origin and direction vectors; avoids allocating coordinate pairs
  // inside the pixel loops and uses the same guide as the portrait preview.
  final (startX, startY, dxX, dxY, dyX, dyY) = switch (rotation) {
    90 => (top, height - 1 - left, 0, -1, 1, 0),
    180 => (width - 1 - left, height - 1 - top, -1, 0, 0, -1),
    270 => (width - 1 - top, left, 0, 1, -1, 0),
    _ => (left, top, 1, 0, 0, 1),
  };
  final luma = Uint8List(w * h);
  double sum = 0;
  for (var y = 0; y < h; y++) {
    var source = (startY + y * dyY) * yRow + (startX + y * dyX) * yPixel;
    final step = dxY * yRow + dxX * yPixel;
    for (var x = 0; x < w; x++) {
      final value = yBytes[source];
      luma[y * w + x] = value;
      sum += value;
      source += step;
    }
  }
  double lapSum = 0, squares = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x,
          lap = luma[i - 1] +
              luma[i + 1] +
              luma[i - w] +
              luma[i + w] -
              4 * luma[i];
      lapSum += lap;
      squares += lap * lap;
    }
  }
  final n = (w - 2) * (h - 2),
      mean = lapSum / n,
      variance = squares / n - mean * mean;
  final result = <String, dynamic>{
    'roiWidth': w,
    'roiHeight': h,
    'luminance': sum / (w * h),
    'sharpness': variance < 0 ? 0.0 : variance
  };
  if (input['encodeJpeg'] != false || input['encodeRgb'] == true) {
    final output = img.Image(width: w, height: h);
    final rgb = output.data!.buffer.asUint8List();
    var index = 0;
    for (var y = 0; y < h; y++) {
      var sx = startX + y * dyX, sy = startY + y * dyY;
      for (var x = 0; x < w; x++) {
        final yy = luma[y * w + x],
            u = uBytes[(sy ~/ 2) * uRow + (sx ~/ 2) * uPixel] - 128,
            v = vBytes[(sy ~/ 2) * vRow + (sx ~/ 2) * vPixel] - 128;
        rgb[index++] = (yy + 1.402 * v).round().clamp(0, 255);
        rgb[index++] = (yy - .344136 * u - .714136 * v).round().clamp(0, 255);
        rgb[index++] = (yy + 1.772 * u).round().clamp(0, 255);
        sx += dxX;
        sy += dxY;
      }
    }
    if (input['encodeRgb'] == true) result['rgb'] = rgb;
    if (input['encodeJpeg'] != false) {
      result['jpeg'] = Uint8List.fromList(img.encodeJpg(output, quality: 85));
    }
  }
  return result;
}

/// Encode only selected frames after collection; JPEG work cannot stall the
/// quality stream or reset an otherwise valid five-frame burst.
List<String> encodeCameraBurst(List<Map<String, dynamic>> frames) => [
      for (final frame in frames)
        base64Encode(processCameraFrame({...frame, 'encodeJpeg': true})['jpeg']
            as Uint8List),
    ];
