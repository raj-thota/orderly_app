/// In-memory cache for signed storage URLs. Entries are dropped shortly
/// before their real expiry so callers re-sign instead of serving a URL
/// that dies mid-render.
class SignedUrlCache {
  SignedUrlCache({
    this.ttl = const Duration(hours: 1),
    this.refreshMargin = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final Duration refreshMargin;
  final DateTime Function() _clock;
  final Map<String, _Entry> _entries = {};

  String? get(String path) {
    final entry = _entries[path];
    if (entry == null) return null;
    if (_clock().isAfter(entry.expiresAt.subtract(refreshMargin))) {
      _entries.remove(path);
      return null;
    }
    return entry.url;
  }

  void put(String path, String url) {
    _entries[path] = _Entry(url, _clock().add(ttl));
  }
}

class _Entry {
  _Entry(this.url, this.expiresAt);
  final String url;
  final DateTime expiresAt;
}
