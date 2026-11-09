import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/features/cockpit/status_latch.dart';

void main() {
  final t0 = DateTime(2026, 10, 30, 12);

  test(
    'Haltezeiten: zwei Minuten bis „nicht verfügbar“, 20 s bis „wieder da“',
    () {
      expect(StatusHold.dataLost, const Duration(minutes: 2));
      expect(StatusHold.dataBack, const Duration(seconds: 20));
      final latch = StatusLatch(
        raiseAfter: StatusHold.dataLost,
        clearAfter: StatusHold.dataBack,
      );
      expect(latch.update(true, t0), isNull);
      expect(latch.update(true, t0.add(const Duration(seconds: 119))), isNull);
      expect(latch.update(true, t0.add(const Duration(seconds: 120))), isTrue);
      expect(latch.update(false, t0.add(const Duration(seconds: 130))), isNull);
      expect(
        latch.update(false, t0.add(const Duration(seconds: 150))),
        isFalse,
      );
    },
  );

  test('„wieder da“ nur nach einer gesprochenen Ansage', () {
    final a = DataAnnouncer();
    expect(a.restored(), isFalse, reason: 'nichts angesagt');
    expect(a.lost(t0), isTrue);
    expect(a.restored(), isTrue);
    expect(a.restored(), isFalse, reason: 'nur einmal');
  });

  test('„nicht verfügbar“ nicht doppelt, auch nicht beim Losfahren', () {
    final a = DataAnnouncer();
    expect(a.lost(t0), isTrue);
    expect(a.lost(t0.add(const Duration(minutes: 1))), isFalse);
    expect(
      a.lost(t0.add(const Duration(minutes: 30))),
      isFalse,
      reason: 'bis „wieder da“ gesprochen ist',
    );
  });

  test('höchstens ein Paar je 5 min', () {
    final a = DataAnnouncer();
    expect(a.lost(t0), isTrue);
    expect(a.restored(), isTrue);
    expect(a.lost(t0.add(const Duration(minutes: 4, seconds: 59))), isFalse);
    expect(a.restored(), isFalse, reason: 'zu früh gewesen, also stumm');
    expect(a.lost(t0.add(const Duration(minutes: 5))), isTrue);
  });

  test('Ausfall im Stand aufgelaufen: Ansage bei Fahrtbeginn, Rückkehr im Stand stumm', () {
    final a = DataAnnouncer();
    expect(a.lost(t0), isTrue); // erster Aufruf beim Losfahren
    a.restoredSilently(); // zurück, aber im Stand
    expect(a.lost(t0.add(const Duration(minutes: 6))), isTrue);
  });

  test('reset vergisst alles', () {
    final a = DataAnnouncer();
    a.lost(t0);
    a.reset();
    expect(a.lost(t0.add(const Duration(seconds: 1))), isTrue);
  });
}
