import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'camera_geometry.dart';
import 'strings.dart';

class ScannerView extends ConsumerWidget {
  final CameraController? camera;
  final CameraGeometry geometry;
  final bool registration, ready, busy, detector;
  final List<String> photos;
  final String instruction;
  final String? error;
  final Rect? detection;
  final VoidCallback? onCapture, onUndo, onGuided;
  final VoidCallback onRetry, onBack;
  const ScannerView(
      {super.key,
      required this.camera,
      required this.geometry,
      required this.registration,
      required this.ready,
      required this.busy,
      required this.detector,
      required this.photos,
      required this.instruction,
      required this.onCapture,
      required this.onRetry,
      required this.onBack,
      this.onUndo,
      this.onGuided,
      this.error,
      this.detection});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const green = Color(0xffb2f53c);
    final color = ready ? green : Colors.amber;
    final guide = geometry.guide;
    final count = photos.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light
            .copyWith(statusBarColor: Colors.transparent),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xff132b20))),
          if (camera?.value.isInitialized == true)
            Positioned.fromRect(
                rect: geometry.image, child: CameraPreview(camera!))
          else if (error == null)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (error == null) ...[
            Positioned.fromRect(
                rect: guide.inflate(9),
                child: IgnorePointer(
                    child: CustomPaint(painter: _Reticle(color)))),
            if (detection != null && detector)
              Positioned.fromRect(
                  rect: Rect.fromLTWH(
                      guide.left + detection!.left * guide.width,
                      guide.top + detection!.top * guide.height,
                      detection!.width * guide.width,
                      detection!.height * guide.height),
                  child: IgnorePointer(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              border: Border.all(color: color, width: 2))))),
            Positioned(
                left: guide.left,
                width: guide.width,
                top: guide.top - 58,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: ready ? green : Colors.black87,
                        borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Text(tr(ref, instruction),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: ready ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w700))))),
          ],
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                  bottom: false,
                  child: Column(children: [
                    Row(children: [
                      IconButton(
                          tooltip: tr(ref, 'Back'),
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white)),
                      Expanded(
                          child: Text(
                              tr(
                                  ref,
                                  registration
                                      ? 'Capture muzzle'
                                      : 'Verify animal'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(color: Colors.white))),
                    ]),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(24)),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                          Icons.cleaning_services_outlined,
                                          color: Colors.white),
                                      const SizedBox(width: 12),
                                      Flexible(
                                          child: Text(
                                              tr(ref, 'Wipe muzzle dry'),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                    ])))),
                  ]))),
          if (error != null)
            Center(
                child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(24),
                    color: Colors.black87,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(tr(ref, error!),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white)),
                      TextButton(
                          onPressed: onRetry,
                          child: Text(tr(ref, 'Try again'))),
                    ]))),
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ColoredBox(
                  color: Colors.black.withValues(alpha: .7),
                  child: SafeArea(
                      top: false,
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            if (registration) ...[
                              Text('${tr(ref, 'Photos')} $count / 5',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < 5; i++)
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          child: SizedBox(
                                              width: 36,
                                              height: 36,
                                              child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  child: i < count
                                                      ? Image.memory(
                                                          base64Decode(
                                                              photos[i]),
                                                          fit: BoxFit.cover,
                                                          cacheWidth: 72)
                                                      : ColoredBox(
                                                          color: Colors.white12,
                                                          child: Center(
                                                              child: Text(
                                                                  '${i + 1}',
                                                                  style: const TextStyle(
                                                                      color: Colors.white70))))))),
                                  ]),
                              const SizedBox(height: 8),
                              Text(
                                  tr(
                                      ref,
                                      count == 0
                                          ? 'Take five photos of the same muzzle.'
                                          : 'Keep the same animal. Change the angle slightly.'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13)),
                              const SizedBox(height: 10),
                            ],
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  SizedBox(
                                      width: 100,
                                      child: detector
                                          ? TextButton(
                                              onPressed: onGuided,
                                              child: Text(
                                                  tr(ref, 'Use guided capture'),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                      color: Colors.white)))
                                          : Text(tr(ref, 'Guided Reticle'),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12))),
                                  Semantics(
                                      button: true,
                                      label: tr(ref, 'Capture photo'),
                                      enabled: onCapture != null,
                                      child: IconButton(
                                          key: const ValueKey('capture-photo'),
                                          tooltip: tr(ref, 'Capture photo'),
                                          onPressed: onCapture,
                                          iconSize: 62,
                                          padding: const EdgeInsets.all(4),
                                          style: IconButton.styleFrom(
                                              side: BorderSide(
                                                  color: onCapture == null
                                                      ? Colors.white38
                                                      : Colors.white,
                                                  width: 3)),
                                          icon: busy
                                              ? const SizedBox(
                                                  width: 62,
                                                  height: 62,
                                                  child: Padding(
                                                      padding:
                                                          EdgeInsets.all(12),
                                                      child:
                                                          CircularProgressIndicator(
                                                              color: Colors
                                                                  .white)))
                                              : Icon(Icons.circle,
                                                  color: onCapture == null
                                                      ? Colors.white38
                                                      : Colors.white))),
                                  SizedBox(
                                      width: 100,
                                      child: registration && photos.isNotEmpty
                                          ? TextButton(
                                              onPressed: onUndo,
                                              child: Text(
                                                  tr(ref, 'Retake last photo'),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                      color: Colors.white)))
                                          : const SizedBox.shrink()),
                                ]),
                          ]))))),
        ]));
  }
}

class _Reticle extends CustomPainter {
  final Color color;
  _Reticle(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final inner = Rect.fromLTWH(9, 9, size.width - 18, size.height - 18);
    canvas.drawRRect(
        RRect.fromRectAndRadius(inner, const Radius.circular(12)), paint);
    paint
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const arm = 24.0;
    for (final p in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height)
    ]) {
      final dx = p.dx == 0 ? arm : -arm, dy = p.dy == 0 ? arm : -arm;
      canvas.drawLine(p, p + Offset(dx, 0), paint);
      canvas.drawLine(p, p + Offset(0, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Reticle old) => old.color != color;
}
