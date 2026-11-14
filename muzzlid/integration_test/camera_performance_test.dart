import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muzzlid/data/camera_frame.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile real camera processing on the connected handset',
      (tester) async {
    expect(kProfileMode, true,
        reason: 'Run this benchmark with flutter drive --profile');
    final back = (await availableCameras())
        .firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    final camera = CameraController(back, ResolutionPreset.medium,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    final init = Stopwatch()..start();
    await camera.initialize();
    final initializationMs = init.elapsedMilliseconds;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: CameraPreview(camera))));
    await tester.pump(const Duration(milliseconds: 300));
    final first = Completer<Map<String, dynamic>>();
    try {
      await camera.startImageStream((image) {
        if (!first.isCompleted) {
          first.complete({
            'width': image.width,
            'height': image.height,
            'rotation': back.sensorOrientation,
            'planes': image.planes
                .map((p) => {
                      'bytes': Uint8List.fromList(p.bytes),
                      'row': p.bytesPerRow,
                      'pixel': p.bytesPerPixel ?? 1
                    })
                .toList()
          });
        }
      });
      final input = await first.future.timeout(const Duration(seconds: 25));
      await camera.stopImageStream();
      final report = <String, dynamic>{
        'mode': 'profile AOT',
        'device_frame_width': input['width'],
        'device_frame_height': input['height'],
        'camera_initialization_ms': initializationMs,
        'notes':
            'ROI processing includes compute isolate transfer; excludes frame acquisition and device-wide load control'
      };
      for (final encode in [false, true]) {
        final request = {...input, 'encodeJpeg': encode};
        await compute(processCameraFrame, request);
        final samples = <double>[];
        var size = 0;
        for (var i = 0; i < 10; i++) {
          final timer = Stopwatch()..start();
          final result = await compute(processCameraFrame, request);
          samples.add(timer.elapsedMicroseconds / 1000);
          expect((result['luminance'] as double).isFinite, true);
          if (encode) size = (result['jpeg'] as Uint8List).length;
        }
        samples.sort();
        report[encode ? 'capture' : 'preview'] = {
          'median_ms': samples[samples.length ~/ 2],
          'p95_ms': samples.last,
          'samples': samples.length,
          if (encode) 'jpeg_bytes': size
        };
      }
      binding.reportData = report;
      debugPrint('PROFILE CAMERA: $report');
    } finally {
      await camera.dispose();
    }
  });
}
