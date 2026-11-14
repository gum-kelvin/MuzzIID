import 'dart:convert';
import 'package:muzzlid/data/local_model.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:muzzlid/presentation/scanner_screen.dart';
import 'package:muzzlid/presentation/state.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muzzlid/data/camera_frame.dart';
import 'package:muzzlid/data/location_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Android CameraX YUV stream, ROI/JPEG and reopen',
      (tester) async {
    final back = (await availableCameras())
        .firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    for (var attempt = 0; attempt < 2; attempt++) {
      final camera = CameraController(back, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      try {
        await camera.initialize();
        final captured = Completer<Map<String, dynamic>>();
        await camera.startImageStream((frame) {
          if (!captured.isCompleted) {
            captured.complete({
              'width': frame.width,
              'height': frame.height,
              'rotation': back.sensorOrientation,
              'encodeJpeg': true,
              'planes': frame.planes
                  .map((p) => {
                        'bytes': Uint8List.fromList(p.bytes),
                        'row': p.bytesPerRow,
                        'pixel': p.bytesPerPixel ?? 1
                      })
                  .toList()
            });
          }
        });
        final input =
            await captured.future.timeout(const Duration(seconds: 25));
        await camera.stopImageStream();
        final timer = Stopwatch()..start();
        final result = await compute(processCameraFrame, input);
        expect((result['luminance'] as double).isFinite, true);
        expect(result['luminance'], inInclusiveRange(0, 255));
        expect(result['sharpness'], greaterThanOrEqualTo(0));
        final jpeg = result['jpeg'] as Uint8List;
        expect(jpeg.take(2), [255, 216]);
        final processingMs = timer.elapsedMilliseconds;
        int? embeddingMs;
        final engine = AndroidEmbeddingEngine();
        final modelStatus = await engine.status();
        expect(modelStatus['ready'], isA<bool>());
        final detectorStatus = await AndroidEmbeddingEngine.channel
            .invokeMapMethod('detectorStatus');
        expect(detectorStatus?['ready'], isA<bool>());
        if (modelStatus['ready'] == true) {
          final embeddingTimer = Stopwatch()..start();
          final embedding = await engine.embed(
              base64Encode(jpeg), modelStatus['version'] as String);
          embeddingMs = embeddingTimer.elapsedMilliseconds;
          expect(embedding, hasLength(512));
          expect(embedding.fold<double>(0, (sum, v) => sum + v * v),
              closeTo(1, .0001));
        }
        debugPrint(
            'DEVICE MODEL: embedding ready=${modelStatus['ready']}, detector ready=${detectorStatus?['ready']}');
        binding.reportData = {
          'camera_width': input['width'],
          'camera_height': input['height'],
          'planes': (input['planes'] as List).length,
          'processing_ms': processingMs,
          'embedding_ms': embeddingMs,
          'jpeg_bytes': jpeg.length
        };
        debugPrint('DEVICE CAMERA: ${binding.reportData}');
      } finally {
        await camera.dispose();
      }
    }
  });
  testWidgets('real Android GPS supplies a timestamped fix', (tester) async {
    final fix = await DeviceLocationService().locate();
    expect(fix.latitude, inInclusiveRange(-90, 90));
    expect(fix.longitude, inInclusiveRange(-180, 180));
    expect(fix.accuracy, greaterThanOrEqualTo(0));
    expect(fix.fresh(DateTime.now()), true);
    debugPrint(
        'DEVICE GPS: timestamp valid, accuracy ${fix.accuracy.round()} m');
  });
  testWidgets('real scanner survives pause and completes five gated frames',
      (tester) async {
    List<String>? captured;
    Duration? collectionDuration;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          languageProvider
              .overrideWith((ref) => LanguageController(persist: false))
        ],
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: FilledButton(
                        onPressed: () async {
                          captured = await Navigator.push<List<String>>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ScannerScreen(
                                      initialClean: true,
                                      onBurstTiming: (duration) =>
                                          collectionDuration = duration)));
                        },
                        child: const Text('Open device scanner')))))));
    await tester.tap(find.text('Open device scanner'));
    await tester.pump(const Duration(milliseconds: 300));
    final detectorAvailable = (await AndroidEmbeddingEngine.channel
            .invokeMapMethod('detectorStatus'))?['ready'] ==
        true;
    if (detectorAvailable) {
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use guided capture'));
      await tester.pump();
    }
    await tester.tap(find.byType(CheckboxListTile).last);
    Future<void> waitReady() async {
      for (var i = 0;
          i < 100 && find.text('Ready to capture').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      debugPrint(
          'DEVICE SCANNER STATE: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(' | ')}');
      expect(find.text('Ready to capture'), findsOneWidget,
          reason:
              'The current camera scene should pass focus/exposure in the guided ROI');
    }

    await waitReady();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 300));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // Hygiene/framing acknowledgements remain, but a partial burst resets.
    await waitReady();
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    final directory = await getApplicationSupportDirectory();
    final screenshots = Directory('${directory.path}/ui-test-screenshots');
    await screenshots.create(recursive: true);
    await File('${screenshots.path}/camera-device.png')
        .writeAsBytes(await binding.takeScreenshot('camera-device'));
    await tester.tap(find.byIcon(Icons.camera_alt));
    for (var i = 0; i < 100 && captured == null; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(captured, hasLength(5));
    expect(collectionDuration!.inMilliseconds, inInclusiveRange(1500, 2500));
    debugPrint(
        'DEVICE COLLECTION: ${collectionDuration!.inMilliseconds} ms for five valid raw frames');
    expect(tester.takeException(), isNull);
    debugPrint(
        'DEVICE BURST: five actual CameraX crops collected after pause/resume');
  });
}
