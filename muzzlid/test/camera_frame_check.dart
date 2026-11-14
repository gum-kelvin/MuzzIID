// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../lib/data/camera_frame.dart';

void main() {
  for (final rotation in [0, 90, 180, 270]) {
    const w = 64, h = 48;
    final input = <String, dynamic>{
      'width': w,
      'height': h,
      'rotation': rotation,
      'planes': [
        {
          'bytes': Uint8List.fromList(
              List.generate(w * h, (i) => i.isEven ? 190 : 60)),
          'row': w,
          'pixel': 1
        },
        {
          'bytes': Uint8List.fromList(List.filled(w * h ~/ 4, 128)),
          'row': w ~/ 2,
          'pixel': 1
        },
        {
          'bytes': Uint8List.fromList(List.filled(w * h ~/ 4, 128)),
          'row': w ~/ 2,
          'pixel': 1
        },
      ]
    };
    final result = processCameraFrame(input);
    final preview = processCameraFrame({...input, 'encodeJpeg': false});
    if (preview.containsKey('jpeg') ||
        preview['sharpness'] != result['sharpness'] ||
        preview['luminance'] != result['luminance']) {
      throw StateError(
          'Preview must preserve quality metrics without JPEG work');
    }
    final detector =
        processCameraFrame({...input, 'encodeJpeg': false, 'encodeRgb': true});
    if (detector.containsKey('jpeg') ||
        (detector['rgb'] as Uint8List).length !=
            (detector['roiWidth'] as int) *
                (detector['roiHeight'] as int) *
                3 ||
        detector['luminance'] != result['luminance']) {
      throw StateError('Detector RGB packet does not match the camera ROI');
    }
    final decoded = img.decodeJpg(result['jpeg'] as Uint8List);
    if (decoded == null ||
        decoded.width <= 0 ||
        decoded.height <= 0 ||
        !(result['luminance'] as double).isFinite ||
        (result['sharpness'] as double) < 0) {
      throw StateError('Invalid frame conversion $rotation');
    }
  }
  print(
      'PASS: YUV ROI conversion, four sensor rotations, quality metrics, JPEG encoding');
}
