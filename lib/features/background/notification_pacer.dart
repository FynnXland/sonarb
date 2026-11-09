import 'dart:async';

/// Gibt Texte nur bei Änderung weiter und höchstens einmal je [minGap].
/// Was dazwischen kommt, wird gesammelt; nach der Pause zählt nur der jüngste Text.
class NotificationPacer {
  NotificationPacer(this._send, {this.minGap = const Duration(seconds: 1)});

  final void Function(String text) _send;
  final Duration minGap;

  String? _sent;
  String? _waiting;
  Timer? _cooldown;

  void submit(String text) {
    if (_cooldown != null) {
      _waiting = text;
      return;
    }
    if (text == _sent) return;
    _emit(text);
  }

  void _emit(String text) {
    _sent = text;
    _send(text);
    _cooldown = Timer(minGap, _afterCooldown);
  }

  void _afterCooldown() {
    _cooldown = null;
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && waiting != _sent) _emit(waiting);
  }

  /// Vergisst den letzten Text, z. B. wenn die Benachrichtigung neu angelegt wird.
  void reset({String? sent}) {
    _cooldown?.cancel();
    _cooldown = null;
    _waiting = null;
    _sent = sent;
  }
}
