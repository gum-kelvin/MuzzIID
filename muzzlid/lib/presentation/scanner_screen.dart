import '../data/local_model.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/camera_frame.dart';
import '../domain/capture_policy.dart';
import 'strings.dart';
import 'field_state.dart';
import '../domain/field_records.dart';
import '../domain/verification.dart';
import 'result_screen.dart';
import 'capture_delivery.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  final bool enrol, initialClean;
  final GeoFix? scanGps;
  final ValueChanged<Duration>? onBurstTiming;
  const ScannerScreen(
      {super.key,
      this.enrol = true,
      this.scanGps,
      this.initialClean = false,
      this.onBurstTiming});
  @override
  ConsumerState<ScannerScreen> createState() => _ScannerState();
}

class _ScannerState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  bool clean = false,
      framed = false,
      processing = false,
      armed = false,
      finished = false;
  String? error;
  int generation = 0;
  int? lastAnalysedTimestamp;
  final burst = EnrolmentBurst();
  final clock = Stopwatch()..start();
  final frames = <Map<String, dynamic>>[];
  int? armedAt;
  String instruction = 'Hold steady';
  bool quality = false;
  bool detectorEnabled = false;
  Rect? detectedBox;
  Future<void> loadDetector() async {
    try {
      final status = await AndroidEmbeddingEngine.channel
          .invokeMapMethod("detectorStatus");
      final settings = await ref.read(settingsProvider.future);
      if (mounted && status?["ready"] == true && settings['guided'] != true) {
        setState(() => detectorEnabled = true);
      }
    } catch (_) {
      /* Guided capture remains available when the detector cannot load. */
    }
  }

  final delivery = CaptureDelivery();
  void whenResumed(VoidCallback action) {
    delivery.deliver(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) action();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  @override
  void initState() {
    super.initState();
    clean = widget.initialClean;
    WidgetsBinding.instance.addObserver(this);
    open();
    loadDetector();
  }

  Future<void> open() async {
    final token = ++generation;
    try {
      final previous = camera;
      camera = null;
      await previous?.dispose();
      final cameras = await availableCameras();
      final back = cameras
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
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted && token == generation) {
        setState(() => error =
            'Camera unavailable. Check camera permission in Android settings.');
      }
    }
  }

  void reset() {
    armed = false;
    burst.reset();
    frames.clear();
    lastAnalysedTimestamp = null;
    armedAt = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      delivery.setActive(false);
      generation++;
      camera?.dispose();
      camera = null;
      if (!finished) reset();
    } else if (state == AppLifecycleState.resumed) {
      delivery.setActive(true);
      if (camera == null && !finished) open();
    }
  }

  Future<void> analyse(CameraImage image, int token) async {
    if (processing || finished || token != generation) return;
    processing = true;
    bool completing = false;
    final acquiredAt = clock.elapsedMilliseconds;
    try {
      final input = <String, dynamic>{
        'encodeJpeg': false,
        'encodeRgb': detectorEnabled,
        'width': image.width,
        'height': image.height,
        'rotation': camera!.description.sensorOrientation,
        'planes': image.planes
            .map((p) => {
                  'bytes': Uint8List.fromList(p.bytes),
                  'row': p.bytesPerRow,
                  'pixel': p.bytesPerPixel ?? 1
                })
            .toList()
      };
      final result = await compute(processCameraFrame, input);
      if (!mounted || token != generation) return;
      final light = result['luminance'] as double,
          focus = result['sharpness'] as double;
      bool localized = framed;
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
      final good = clean && localized && qualityIssue(focus, light) == null;
      final nextInstruction = !clean
          ? 'Wipe muzzle dry'
          : !localized
              ? 'Confirm the whole muzzle fills the guide.'
              : focus <= 120
                  ? 'Hold steady'
                  : light < 45
                      ? 'More light needed'
                      : light > 215
                          ? 'Reduce glare'
                          : armed
                              ? 'Hold steady · capturing'
                              : 'Ready to capture';
      if (detectorEnabled ||
          quality != good ||
          instruction != nextInstruction) {
        setState(() {
          quality = good;
          instruction = nextInstruction;
        });
      }
      if (!armed || armedAt == null || acquiredAt < armedAt!) return;
      final timestamp = acquiredAt;
      if (lastAnalysedTimestamp != null &&
          timestamp - lastAnalysedTimestamp! > 500) {
        burst.reset();
        frames.clear();
      }
      lastAnalysedTimestamp = timestamp;
      final before = burst.count;
      burst.accept(timestampMs: timestamp, valid: good);
      if (burst.count == 0 || burst.count < before) frames.clear();
      if (burst.count > frames.length) {
        frames.add(input);
      }
      if (before != burst.count) setState(() {});
      if ((widget.enrol && burst.complete) || (!widget.enrol && good)) {
        final selectedFrames = List<Map<String, dynamic>>.unmodifiable(frames);
        if (widget.enrol) {
          widget.onBurstTiming?.call(Duration(milliseconds: burst.durationMs));
        }
        completing = true;
        finished = true;
        armed = false;
        setState(() => instruction = 'Preparing capture');
        // Camera release may race an OS pause after the payload is complete.
        try {
          await camera?.stopImageStream();
        } catch (_) {/* Payload is already owned. */}
        final completedFrames =
            snapshotCapture(await compute(encodeCameraBurst, selectedFrames));
        if (!mounted) return;
        if (widget.enrol) {
          whenResumed(() => Navigator.pop(context, completedFrames));
        } else {
          setState(() => instruction = 'Saving scan');
          final gps =
              widget.scanGps != null && widget.scanGps!.fresh(DateTime.now())
                  ? widget.scanGps!
                  : await ref.read(locationServiceProvider).locate();
          final time = DateTime.now().toUtc();
          final id = 'SCAN-${time.microsecondsSinceEpoch}';
          await ref.read(activityProvider.notifier).add(FieldActivity(
              id: id,
              kind: 'Verification',
              animalId: '',
              time: time,
              gps: gps,
              frames: [completedFrames.first]));
          if (mounted) setState(() => instruction = 'Comparing local records');
          VerificationResult result;
          try {
            result = await ref
                .read(verificationServiceProvider)
                .verify(completedFrames.first, gps)
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
                .settle(id, result.status.name);
          }
          if (!mounted) return;
          whenResumed(() => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => ResultScreen(
                      result: result,
                      frame: completedFrames.first,
                      gps: gps,
                      time: time))));
        }
      }
    } catch (_) {
      if (mounted && (token == generation || completing)) {
        setState(() {
          finished = false;
          quality = false;
          instruction = 'Try again';
          error = 'Camera processing stopped. Try again.';
          reset();
        });
      }
    } finally {
      processing = false;
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
  Widget build(BuildContext context) {
    final c = camera;
    return Scaffold(
        backgroundColor: const Color(0xff132b20),
        appBar: AppBar(
            backgroundColor: const Color(0xff132b20),
            foregroundColor: Colors.white,
            title: Text(
                tr(ref, widget.enrol ? 'Capture muzzle' : 'Verify animal'))),
        body: SafeArea(
            child: Column(children: [
          if (error != null)
            Expanded(
                child: Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(tr(ref, error!),
                              style: const TextStyle(color: Colors.white)),
                          TextButton(
                              onPressed: open,
                              child: Text(tr(ref, 'Try again')))
                        ]))))
          else
            Expanded(
                child: c == null || !c.value.isInitialized
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: AspectRatio(
                            aspectRatio: 1 / c.value.aspectRatio,
                            child: Stack(fit: StackFit.expand, children: [
                              CameraPreview(c),
                              FractionallySizedBox(
                                  widthFactor: .75,
                                  heightFactor: .45,
                                  alignment: const Alignment(0, .455),
                                  child: Container(
                                      decoration: BoxDecoration(
                                          border: Border.all(
                                              color: quality
                                                  ? const Color(0xff64c08a)
                                                  : Colors.amber,
                                              width: 3),
                                          borderRadius:
                                              BorderRadius.circular(12)))),
                              if (detectorEnabled && detectedBox != null)
                                FractionallySizedBox(
                                    widthFactor: .75,
                                    heightFactor: .45,
                                    alignment: const Alignment(0, .455),
                                    child: LayoutBuilder(
                                        builder: (context, bounds) =>
                                            Stack(children: [
                                              Positioned(
                                                  left: detectedBox!.left *
                                                      bounds.maxWidth,
                                                  top: detectedBox!.top *
                                                      bounds.maxHeight,
                                                  width: detectedBox!.width *
                                                      bounds.maxWidth,
                                                  height: detectedBox!.height *
                                                      bounds.maxHeight,
                                                  child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                          border: Border.all(
                                                              color: quality
                                                                  ? Colors
                                                                      .greenAccent
                                                                  : Colors
                                                                      .amber,
                                                              width: 2))))
                                            ]))),
                              Positioned(
                                  top: 16,
                                  left: 16,
                                  right: 16,
                                  child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      child: Text(tr(ref, instruction),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600)))),
                            ])))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                CheckboxListTile(
                    value: clean,
                    onChanged: finished
                        ? null
                        : (v) => setState(() {
                              clean = v!;
                              reset();
                            }),
                    title: Text(tr(ref, 'Wipe muzzle dry'),
                        style: const TextStyle(color: Colors.white))),
                if (detectorEnabled)
                  TextButton(
                      onPressed: finished
                          ? null
                          : () => setState(() {
                                detectorEnabled = false;
                                detectedBox = null;
                                reset();
                              }),
                      child: Text(tr(ref, 'Use guided capture')))
                else
                  CheckboxListTile(
                      value: framed,
                      onChanged: finished
                          ? null
                          : (v) => setState(() {
                                framed = v!;
                                reset();
                              }),
                      title: Text(
                          tr(ref, 'Confirm the whole muzzle fills the guide.'),
                          style: const TextStyle(color: Colors.white))),
                Text(
                    '${tr(ref, detectorEnabled ? 'Automatic muzzle detection' : 'Guided Reticle')} · ${burst.count} / ${widget.enrol ? 5 : 1}',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                if (finished) const LinearProgressIndicator(),
                FilledButton(
                    onPressed: !quality || armed || finished
                        ? null
                        : () => setState(() {
                              reset();
                              armed = true;
                              armedAt = clock.elapsedMilliseconds;
                            }),
                    child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                            armed ? Icons.hourglass_top : Icons.camera_alt,
                            size: 32))),
                const SizedBox(height: 16),
              ])),
        ])));
  }
}
