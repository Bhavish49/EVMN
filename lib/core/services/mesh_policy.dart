class BoundedDedupCache {
  BoundedDedupCache({this.capacity = 512}) : assert(capacity > 0);

  final int capacity;
  final Set<String> _ids = <String>{};

  /// Returns true only the first time an ID is recorded.
  bool recordIfNew(String id) {
    if (!_ids.add(id)) {
      return false;
    }
    if (_ids.length > capacity) {
      _ids.remove(_ids.first);
    }
    return true;
  }

  bool contains(String id) => _ids.contains(id);
  int get length => _ids.length;
}

class ForwardingRateLimit {
  ForwardingRateLimit({
    this.minimumInterval = const Duration(milliseconds: 600),
  }) : assert(!minimumInterval.isNegative);

  final Duration minimumInterval;
  DateTime? _lastForwardedAt;

  bool allow({DateTime? now}) {
    final current = now ?? DateTime.now();
    final last = _lastForwardedAt;
    if (last != null && current.difference(last) < minimumInterval) {
      return false;
    }
    _lastForwardedAt = current;
    return true;
  }
}
