import 'package:flutter_test/flutter_test.dart';
import 'package:sonarb/core/geo/geo.dart';
import 'package:sonarb/core/model/alert_point.dart';
import 'package:sonarb/features/background/monitor_snapshot.dart';
import 'package:sonarb/features/background/notification_pacer.dart';

const _camera = AlertPoint(
  id: 'osm:node/1',
  kind: AlertKind.speedCamera,
  position: GeoPoint(52.5, 13.41),
  source: 'osm',
);

void main() {
  group('notificationLine', () {
    test('Fahrt: Tempo, Limit, nächster Punkt', () {
      expect(
        notificationLine(
          const MonitorSnapshot(
            driving: true,
            speedKmh: 51.6,
            limitKmh: 50,
            next: _camera,
            nextMeters: 412,
          ),
        ),
        '52 km/h · Limit 50 · Blitzer in 400 m',
      );
    });

    test('Fahrt ohne Limit und ohne Punkt', () {
      expect(
        notificationLine(const MonitorSnapshot(driving: true, speedKmh: 80)),
        '80 km/h',
      );
    });

    test('Stand', () {
      expect(
        notificationLine(const MonitorSnapshot()),
        'Bereit · erkennt Fahrt automatisch',
      );
      expect(
        notificationLine(const MonitorSnapshot(dataUnavailable: true)),
        'Bereit · Daten offline',
      );
    });

    test('Verbindungsverlust während der Fahrt', () {
      expect(
        notificationLine(
          const MonitorSnapshot(driving: true, speedKmh: 50, gpsLost: true),
        ),
        'Kein GPS-Signal',
      );
      expect(
        notificationLine(
          const MonitorSnapshot(
            driving: true,
            speedKmh: 50,
            limitKmh: 50,
            dataUnavailable: true,
          ),
        ),
        '50 km/h · Limit 50 · Daten offline',
      );
    });

    test('Hotspot-Art im Text', () {
      const p = AlertPoint(
        id: 'hotspot:1',
        kind: AlertKind.hotspot,
        position: GeoPoint(52.5, 13.41),
        source: 'hotspot',
        reportKind: HotspotKind.mobileCamera,
      );
      expect(pointLabel(p), 'Mobiler Blitzer');
    });

    test('Entfernung grob gerundet', () {
      expect(roughDistance(12), '0 m');
      expect(roughDistance(424), '400 m');
      expect(roughDistance(426), '450 m');
      expect(roughDistance(980), '1,0 km');
      expect(roughDistance(1260), '1,3 km');
    });
  });

  group('NotificationPacer', () {
    testWidgets('nur Änderungen, höchstens einmal pro Sekunde, zuletzt gilt', (
      tester,
    ) async {
      final sent = <String>[];
      final pacer = NotificationPacer(sent.add);
      pacer.submit('a');
      pacer.submit('b');
      pacer.submit('c');
      expect(sent, ['a']);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(sent, ['a', 'c']);

      await tester.pump(const Duration(milliseconds: 1000));
      pacer.submit('c');
      expect(sent, ['a', 'c']);

      pacer.submit('d');
      expect(sent, ['a', 'c', 'd']);
      pacer.reset();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('zurück zum gesendeten Text in der Pause: nichts neu', (
      tester,
    ) async {
      final sent = <String>[];
      final pacer = NotificationPacer(sent.add);
      pacer.submit('a');
      pacer.submit('b');
      pacer.submit('a');
      await tester.pump(const Duration(seconds: 2));
      expect(sent, ['a']);
    });
  });
}
