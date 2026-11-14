// ignore_for_file: avoid_relative_lib_imports, avoid_print
import '../lib/presentation/capture_delivery.dart';

void main() {
  final cameraFrames = List.filled(5, 'jpeg', growable: true);
  final owned = snapshotCapture(cameraFrames);
  final delivery = CaptureDelivery();
  var deliveries = 0;
  delivery.setActive(false);
  cameraFrames.clear();
  delivery.deliver(() {
    if (owned.length != 5) throw StateError('Payload lost');
    deliveries++;
  });
  if (deliveries != 0) throw StateError('Navigated while paused');
  delivery.setActive(true);
  delivery.setActive(true);
  if (deliveries != 1) {
    throw StateError('Completion must deliver once on resume');
  }
  delivery.setActive(false);
  delivery.deliver(() => deliveries++);
  delivery.close();
  delivery.setActive(true);
  if (deliveries != 1) throw StateError('Disposed route must not navigate');
  print(
      'PASS: completed frames survive buffer reset; pause/resume delivers once; disposed routes do not navigate');
}
