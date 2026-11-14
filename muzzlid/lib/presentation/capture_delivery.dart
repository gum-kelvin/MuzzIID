/// Keeps completion independent of camera buffers and defers navigation while
/// Android has paused the route (permission dialogs, app switching, screen lock).
class CaptureDelivery {
  bool _active = true, _closed = false;
  void Function()? _pending;
  void setActive(bool active) {
    if (_closed) return;
    _active = active;
    if (active) {
      final action = _pending;
      _pending = null;
      action?.call();
    }
  }

  void deliver(void Function() action) {
    if (_closed) return;
    if (_active) {
      action();
    } else {
      _pending = action;
    }
  }

  void close() {
    _closed = true;
    _pending = null;
  }
}

List<String> snapshotCapture(List<String> frames) =>
    List<String>.unmodifiable(frames);
