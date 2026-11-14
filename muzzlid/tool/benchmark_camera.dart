// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';
import 'package:muzzlid/data/camera_frame.dart';

void main() {
  final frame = <String, dynamic>{
    'width': 640,
    'height': 480,
    'rotation': 90,
    'planes': [
      {
        'bytes': Uint8List.fromList(
            List.generate(640 * 480, (i) => i.isEven ? 190 : 60)),
        'row': 640,
        'pixel': 1
      },
      {
        'bytes': Uint8List.fromList(List.filled(320 * 240, 128)),
        'row': 320,
        'pixel': 1
      },
      {
        'bytes': Uint8List.fromList(List.filled(320 * 240, 128)),
        'row': 320,
        'pixel': 1
      },
    ]
  };
  final measurements = <String, dynamic>{
    'environment':
        'host Dart JIT; synthetic 640x480 YUV ROI; computation only, excludes isolate/message/camera cost'
  };
  for (final encode in [false, true]) {
    frame['encodeJpeg'] = encode;
    for (var i = 0; i < 3; i++) {
      processCameraFrame(frame);
    }
    final times = <double>[];
    for (var i = 0; i < 15; i++) {
      final clock = Stopwatch()..start();
      processCameraFrame(frame);
      times.add(clock.elapsedMicroseconds / 1000);
    }
    times.sort();
    measurements[encode ? 'capture' : 'preview'] = {
      'median_ms': times[times.length ~/ 2],
      'p95_ms': times[(times.length * .95).floor()]
    };
  }
  print(jsonEncode(measurements));
}
