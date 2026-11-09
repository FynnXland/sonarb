import 'dart:async';

class _Waiter {
  _Waiter(this.priority, this.order, this.seq);

  final int priority;
  final double order;
  final int seq;
  final Completer<void> go = Completer<void>();
}

/// Begrenzt gleichzeitige Overpass-Anfragen. Wartende laufen nach Dringlichkeit
/// (kleinere `priority` zuerst), bei gleicher Dringlichkeit nach `order` (z. B. Abstand), dann nach Eingang.
class PriorityGate {
  PriorityGate(this.limit);

  final int limit;
  int _running = 0;
  int _seq = 0;
  final List<_Waiter> _waiting = [];

  Future<T> run<T>(
    Future<T> Function() job, {
    int priority = 0,
    double order = 0,
  }) async {
    if (_running >= limit) {
      final w = _Waiter(priority, order, _seq++);
      final at = _waiting.indexWhere((o) => _before(w, o));
      _waiting.insert(at < 0 ? _waiting.length : at, w);
      await w.go.future;
    } else {
      _running++;
    }
    try {
      return await job();
    } finally {
      if (_waiting.isEmpty) {
        _running--;
      } else {
        _waiting.removeAt(0).go.complete(); // Platz direkt weiterreichen
      }
    }
  }

  static bool _before(_Waiter a, _Waiter b) {
    if (a.priority != b.priority) return a.priority < b.priority;
    return a.order < b.order;
  }
}
