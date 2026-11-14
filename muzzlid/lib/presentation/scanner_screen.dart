import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local_model.dart';
import '../data/camera_frame.dart';
import '../domain/capture_policy.dart';
import '../domain/registration_photos.dart';
import '../domain/field_records.dart';
import '../domain/verification.dart';
import 'field_state.dart';
import 'result_screen.dart';
import 'capture_delivery.dart';
import 'camera_geometry.dart';
import 'scanner_view.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  final bool registration;
  const ScannerScreen({super.key, this.registration = true});
  @override
  ConsumerState<ScannerScreen> createState() => _ScannerState();
}

class _ScannerState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  bool processing = false, armed = false, encoding = false, finished = false;
  bool resolving = false, quality = false, detectorEnabled = false;
  String? error, pendingPhoto;
  String instruction = 'Hold steady';
  int generation = 0, armedAt = 0, noticeUntil = 0;
  final clock = Stopwatch()..start();
  final photos = RegistrationPhotos();
  final delivery = CaptureDelivery();
  CameraGeometry? geometry;
  Rect? detectedBox;
  GeoFix? gps;
  Future<GeoFix?>? gpsRequest;
  DateTime? capturedAt;
  String? scanId;
  bool scanSaved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    open();
    loadDetector();
  }

  Future<GeoFix?> locate() => gpsRequest ??= fetchLocation();
  Future<GeoFix?> fetchLocation() async {
    try {
      return gps = await ref.read(locationServiceProvider).locate();
    } catch (_) {
      return null;
    } finally {
      gpsRequest = null;
    }
  }

  Future<void> loadDetector() async {
    try {
      final status = await AndroidEmbeddingEngine.channel
          .invokeMapMethod('detectorStatus');
      final settings = await ref.read(settingsProvider.future);
      if (mounted && status?['ready'] == true && settings['guided'] != true) {
        setState(() => detectorEnabled = true);
      }
    } catch (_) {/* The manual guide remains available. */}
  }

  void whenResumed(VoidCallback action) => delivery.deliver(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) action();
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      });

  Future<void> open() async {
    final token = ++generation;
    if (mounted) {
      setState(() {
        error = null;
        quality = false;
        instruction = 'Hold steady';
      });
    }
    try {
      final previous = camera;
      camera = null;
      await previous?.dispose();
      final back = (await availableCameras())
          .firstWhere((c) => c.lensDirection == CameraLensDirection.back);
      final next = CameraController(back, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await next.initialize();
      await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || token != generation) {
        await next.dispose();
        return;
      }
      camera = next;
      await next.startImageStream((image) => analyse(image, token));
      if (!widget.registration &&
          (gps == null || !gps!.fresh(DateTime.now()))) {
        locate();
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted && token == generation) {
        setState(() => error =
            'Camera unavailable. Check camera permission in Android settings.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      delivery.setActive(false);
      generation++;
      final previous = camera;
      camera = null;
      previous?.dispose();
      armed = false;
      quality = false;
      instruction = 'Hold steady';
      // Already accepted photos survive pauses; unfinished frame work is discarded.
    } else if (state == AppLifecycleState.resumed) {
      delivery.setActive(true);
      if (camera == null && !finished) open();
    }
  }

  Future<void> analyse(CameraImage image, int token) async {
    if (processing ||
        encoding ||
        finished ||
        token != generation ||
        geometry == null) {
      return;
    }
    processing = true;
    final acquiredAt = clock.elapsedMilliseconds;
    try {
      final roi = geometry!.roi;
      final input = <String, dynamic>{
        'encodeJpeg': false,
        'encodeRgb': detectorEnabled,
        'roi': {
          'x': roi.left,
          'y': roi.top,
          'width': roi.width,
          'height': roi.height
        },
        'width': image.width,
        'height': image.height,
        'rotation': camera!.description.sensorOrientation,
        'planes': image.planes
            .map((p) => {
                  'bytes': Uint8List.fromList(p.bytes),
                  'row': p.bytesPerRow,
                  'pixel': p.bytesPerPixel ?? 1
                })
            .toList(),
      };
      final result = await compute(processCameraFrame, input);
      if (!mounted || token != generation) return;
      bool localized =
          true; // Guided framing is passive, not an acknowledgement gate.
      if (detectorEnabled) {
        final detection = await AndroidEmbeddingEngine.channel.invokeMapMethod(
            'detectRgb', {
          'rgb': result['rgb'],
          'width': result['roiWidth'],
          'height': result['roiHeight']
        });
        if (!mounted || token != generation) return;
        detectedBox = detection?['found'] == true
            ? Rect.fromLTWH(
                (detection!['x'] as num).toDouble(),
                (detection['y'] as num).toDouble(),
                (detection['width'] as num).toDouble(),
                (detection['height'] as num).toDouble())
            : null;
        final box = detectedBox;
        localized = box != null &&
            box.width > 0 &&
            box.height > 0 &&
            box.left >= 0 &&
            box.top >= 0 &&
            box.right <= 1 &&
            box.bottom <= 1 &&
            box.width * box.height >= .4;
      }
      final issue = qualityIssue(
          result['sharpness'] as double, result['luminance'] as double);
      final good = localized && issue == null;
      final text = clock.elapsedMilliseconds < noticeUntil
          ? 'Change the angle slightly before the next photo.'
          : !localized
              ? 'Move the muzzle inside the guide'
              : issue == CaptureIssue.blur
                  ? 'Hold steady'
                  : issue == CaptureIssue.dark
                      ? 'More light needed'
                      : issue == CaptureIssue.glare
                          ? 'Reduce glare'
                          : 'Ready to capture';
      if (detectorEnabled || quality != good || instruction != text) {
        setState(() {
          quality = good;
          instruction = text;
        });
      }
      if (!armed || acquiredAt < armedAt || !good) return;
      armed = false;
      encoding = true;
      setState(() => instruction = 'Preparing capture');
      final photo = (await compute(encodeCameraBurst, [input])).single;
      if (!mounted || token != generation) return;
      if (widget.registration) {
        if (!photos.add(photo, acquiredAt)) {
          noticeUntil = clock.elapsedMilliseconds + 2500;
          setState(() =>
              instruction = 'Change the angle slightly before the next photo.');
          return;
        }
        setState(() {
          quality = false;
        });
        if (!photos.complete) return;
        finished = true;
        await stopStream();
        final completed = snapshotCapture(photos.photos);
        whenResumed(() => Navigator.pop(context, completed));
      } else {
        pendingPhoto = photo;
        capturedAt = DateTime.now().toUtc();
        scanId = 'SCAN-${capturedAt!.microsecondsSinceEpoch}';
        finished = true;
        await stopStream();
        await resolveVerification();
      }
    } catch (_) {
      if (mounted && token == generation) {
        setState(() {
          error = 'Camera processing stopped. Try again.';
          armed = false;
          quality = false;
        });
      }
    } finally {
      final encoded = encoding;
      processing = false;
      encoding = false;
      if (mounted && encoded) setState(() {});
    }
  }

  Future<void> stopStream() async {
    try {
      await camera?.stopImageStream();
    } catch (_) {/* The completed photo payload is owned independently. */}
  }

  Future<void> resolveVerification() async {
    if (resolving || pendingPhoto == null) return;
    setState(() {
      resolving = true;
      error = null;
      instruction = 'Saving scan';
    });
    try {
      final fix =
          gps != null && gps!.fresh(DateTime.now()) ? gps : await locate();
      if (fix == null) {
        if (mounted) {
          setState(() => error =
              'Location unavailable. Allow location access and turn on GPS, then retry.');
        }
        return;
      }
      if (!mounted) return;
      if (!scanSaved) {
        await ref.read(activityProvider.notifier).add(FieldActivity(
            id: scanId!,
            kind: 'Verification',
            animalId: '',
            time: capturedAt!,
            gps: fix,
            frames: [pendingPhoto!]));
        scanSaved = true;
      }
      if (mounted) setState(() => instruction = 'Comparing local records');
      VerificationResult result;
      try {
        result = await ref
            .read(verificationServiceProvider)
            .verify(pendingPhoto!, fix)
            .timeout(const Duration(minutes: 5));
      } catch (_) {
        result = const VerificationResult(VerificationStatus.pending);
      }
      final score = result.confidence;
      if (result.status != VerificationStatus.pending &&
          (score == null ||
              !score.isFinite ||
              score < -1 ||
              score > 1 ||
              (result.status == VerificationStatus.verified &&
                  result.animal == null))) {
        result = const VerificationResult(VerificationStatus.pending);
      }
      if (result.status != VerificationStatus.pending) {
        await ref
            .read(activityProvider.notifier)
            .settle(scanId!, result.status.name);
      }
      if (!mounted) return;
      whenResumed(() => Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => ResultScreen(
                  result: result,
                  frame: pendingPhoto!,
                  gps: fix,
                  time: capturedAt!))));
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to save. Please try again.');
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  @override
  void dispose() {
    generation++;
    delivery.close();
    WidgetsBinding.instance.removeObserver(this);
    camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: LayoutBuilder(builder: (context, constraints) {
        final layout = CameraGeometry(constraints.biggest,
            camera == null ? 2 / 3 : 1 / camera!.value.aspectRatio);
        geometry = layout;
        final busy = armed || encoding || finished || resolving;
        return ScannerView(
            camera: camera,
            geometry: layout,
            registration: widget.registration,
            ready: quality && !busy,
            busy: busy,
            detector: detectorEnabled,
            photos: photos.photos,
            instruction: instruction,
            error: error,
            detection: detectedBox,
            onBack: () => Navigator.pop(context),
            onRetry: pendingPhoto != null ? resolveVerification : open,
            onCapture: !quality || busy || error != null
                ? null
                : () => setState(() {
                      armed = true;
                      instruction = 'Hold steady';
                      armedAt = clock.elapsedMilliseconds;
                    }),
            onUndo: busy
                ? null
                : () => setState(() {
                      photos.undo();
                      noticeUntil = 0;
                    }),
            onGuided: busy
                ? null
                : () => setState(() {
                      detectorEnabled = false;
                      detectedBox = null;
                      quality = false;
                    }));
      }));
}
