/// Guards against handling the same notification tap twice — e.g. when the
/// cold-start launch-details path and the runtime `onDidReceiveNotification
/// Response` callback both fire for one tap.
class TapDeduper {
  TapDeduper({
    Duration window = const Duration(seconds: 2),
    DateTime Function() now = DateTime.now,
  })  : _window = window,
        _now = now;

  final Duration _window;
  final DateTime Function() _now;
  String? _lastPayload;
  DateTime? _lastAt;

  bool shouldHandle(String? payload) {
    if (payload == null || payload.isEmpty) return false;
    final now = _now();
    final lastAt = _lastAt;
    if (_lastPayload == payload &&
        lastAt != null &&
        now.difference(lastAt) < _window) {
      return false;
    }
    _lastPayload = payload;
    _lastAt = now;
    return true;
  }
}
