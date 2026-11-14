/// Five independently requested captures. Exact duplicates never advance progress.
/// Animal identity and angle variation still require the operator's judgement.
class RegistrationPhotos {
  final _photos = <String>[];
  int _lastSample = -1;
  List<String> get photos => List.unmodifiable(_photos);
  int get count => _photos.length;
  bool get complete => count == 5;
  bool add(String jpeg, int sample) {
    if (complete || sample <= _lastSample || _photos.contains(jpeg)) {
      return false;
    }
    _photos.add(jpeg);
    _lastSample = sample;
    return true;
  }

  void undo() {
    if (_photos.isNotEmpty) _photos.removeLast();
  }
}
