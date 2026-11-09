import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarb/features/osm/osm_layer.dart';
import 'package:sonarb/features/osm/overpass_client.dart';

import 'osm_fixtures.dart';

const _main = 'https://main.test/api';
const _second = 'https://second.test/api';

/// Zwei Endpunkte mit steuerbarem Verhalten und einer Uhr, die sich nur im Test bewegt.
class _Rig {
  DateTime clock = DateTime.utc(2026, 5, 1);
  final calls = <String>[];

  /// Verhalten je Host: `ok`, `silent` (Zeitüberschreitung), `refused` (Verbindung scheitert),
  /// `overload` (429).
  final mode = {'main.test': 'ok', 'second.test': 'ok'};

  late final OverpassClient client = OverpassClient(
    client: MockClient((req) async {
      calls.add(req.url.host);
      switch (mode[req.url.host]) {
        case 'silent':
          throw TimeoutException('keine Antwort');
        case 'refused':
          throw const SocketException('Connection refused');
        case 'overload':
          return http.Response('', 429);
        default:
          return http.Response(layerBody(OsmLayer.cameras), 200);
      }
    }),
    endpoints: const [_main, _second],
    now: () => clock,
  );

  Future<Object?> fetch() async {
    calls.clear();
    try {
      await client.fetch(OsmLayer.cameras, [testTile]);
      return null;
    } on OverpassException catch (e) {
      return e;
    }
  }

  void wait(Duration d) => clock = clock.add(d);
}

void main() {
  late _Rig rig;
  setUp(() => rig = _Rig());

  test('toter Zweitserver: nur der erste Versuch wartet, danach wird er übersprungen', () async {
    rig.mode['main.test'] = 'overload'; // der Hauptserver ist da, aber voll
    rig.mode['second.test'] = 'silent';
    expect(await rig.fetch(), isA<OverpassException>());
    expect(rig.calls, [
      'main.test',
      'second.test',
    ], reason: 'erster Versuch probiert beide');

    // Der Hauptserver ist nach seiner Überlastpause wieder dran; der tote bleibt außen vor.
    rig.wait(const Duration(minutes: 2));
    rig.mode['main.test'] = 'ok';
    expect(await rig.fetch(), isNull);
    expect(rig.calls, ['main.test']);

    rig.mode['main.test'] = 'overload';
    rig.wait(const Duration(minutes: 2));
    expect(await rig.fetch(), isA<OverpassException>());
    expect(rig.calls, [
      'main.test',
    ], reason: 'der tote Zweitserver kostet nichts mehr');
  });

  test(
    'Verbindung scheitert zählt wie Schweigen, wenn der andere antwortet',
    () async {
      rig.mode['main.test'] = 'refused';
      expect(await rig.fetch(), isNull);
      expect(rig.calls, ['main.test', 'second.test']);
      expect(await rig.fetch(), isNull);
      expect(rig.calls, ['second.test'], reason: 'Hauptserver ruht');
    },
  );

  test('nach Ablauf der Pause wird der Endpunkt einmal wieder probiert; Erfolg setzt zurück', () async {
    rig.mode['main.test'] = 'silent';
    expect(
      await rig.fetch(),
      isNull,
    ); // Zweitserver antwortet: Hauptserver ruht
    expect(await rig.fetch(), isNull);
    expect(rig.calls, ['second.test']);

    rig.wait(const Duration(minutes: 9, seconds: 50));
    expect(await rig.fetch(), isNull);
    expect(rig.calls, ['second.test'], reason: 'noch nicht abgelaufen');

    rig.wait(const Duration(seconds: 20));
    rig.mode['main.test'] = 'ok';
    expect(await rig.fetch(), isNull);
    expect(rig.calls, ['main.test'], reason: 'wieder dran und antwortet');

    // Zurückgesetzt: bleibt im Dienst und nicht erneut tot.
    expect(await rig.fetch(), isNull);
    expect(rig.calls, ['main.test']);
  });

  test('antwortet er nach der Pause wieder nicht, ruht er erneut', () async {
    rig.mode['main.test'] = 'silent';
    await rig.fetch();
    rig.wait(const Duration(minutes: 11));
    expect(await rig.fetch(), isNull);
    expect(rig.calls, [
      'main.test',
      'second.test',
    ], reason: 'einmal probiert, dann weiter');
    expect(await rig.fetch(), isNull);
    expect(rig.calls, ['second.test']);
  });

  test(
    'beide tot: normale Fehlerkette wie bisher, kein Urteil über die Endpunkte',
    () async {
      rig.mode['main.test'] = 'silent';
      rig.mode['second.test'] = 'silent';
      final e = await rig.fetch() as OverpassException;
      expect(e.reason, OverpassReason.silent);
      expect(rig.calls, ['main.test', 'second.test']);
      // Kein Endpunkt hat geantwortet: vermutlich das Netz. Nach der kurzen Pause werden beide wieder versucht.
      rig.wait(const Duration(seconds: 31));
      expect(await rig.fetch(), isA<OverpassException>());
      expect(rig.calls, ['main.test', 'second.test']);
      // Netz zurück: der Hauptserver ist nicht für 10 Minuten gesperrt.
      rig.mode['main.test'] = 'ok';
      rig.wait(const Duration(minutes: 3));
      expect(await rig.fetch(), isNull);
    },
  );

  test(
    'der Hauptserver ist nie gesperrt, wenn er als Einziger noch antwortet',
    () async {
      expect(await rig.fetch(), isNull); // Hauptserver antwortet: bewährt
      rig.mode['main.test'] = 'silent';
      await rig.fetch(); // Hauptserver ruht, der zweite antwortet
      rig.wait(const Duration(minutes: 1));
      // Nun schweigt der zweite, und der Hauptserver ist wieder gesund: er kommt als Notnagel dran.
      rig.mode['main.test'] = 'ok';
      rig.mode['second.test'] = 'silent';
      expect(await rig.fetch(), isNull);
      expect(rig.calls, ['second.test', 'main.test']);
    },
  );

  test('ein Endpunkt, der nie geantwortet hat, kostet nach einem Fehlschlag keine Frist mehr', () async {
    expect(await rig.fetch(), isNull); // Hauptserver antwortet
    rig.mode['main.test'] = 'silent';
    rig.mode['second.test'] = 'silent';
    // Beide still: der zweite hat nie geantwortet, der Hauptserver vor Kurzem. Der zweite ruht,
    // der Hauptserver bekommt nur die kurze Pause.
    expect(await rig.fetch(), isA<OverpassException>());
    expect(rig.calls, ['main.test', 'second.test']);
    rig.wait(const Duration(seconds: 31));
    expect(await rig.fetch(), isA<OverpassException>());
    expect(rig.calls, ['main.test'], reason: 'der zweite ist als tot gemerkt');
    rig.mode['main.test'] = 'ok';
    rig.wait(const Duration(seconds: 61));
    expect(await rig.fetch(), isNull);
  });

  test(
    'tote Endpunkte werden bei Überlast der anderen nicht angefragt',
    () async {
      rig.mode['main.test'] = 'silent';
      await rig.fetch();
      rig.mode['second.test'] = 'overload';
      rig.wait(const Duration(minutes: 1));
      final e = await rig.fetch() as OverpassException;
      expect(e.reason, OverpassReason.overloaded);
      expect(rig.calls, [
        'second.test',
      ], reason: 'der tote Hauptserver kostet keine Frist');
      expect(e.retryAfter, isNotNull);
      expect(e.retryAfter, lessThanOrEqualTo(const Duration(minutes: 2)));
    },
  );

  test('ein einziger Endpunkt wird nie als tot gemerkt', () async {
    var calls = 0;
    final c = OverpassClient(
      client: MockClient((req) async {
        calls++;
        if (calls == 1) throw TimeoutException('zu langsam');
        return http.Response(layerBody(OsmLayer.cameras), 200);
      }),
      endpoints: const [_main],
      now: () => rig.clock,
    );
    await expectLater(
      c.fetch(OsmLayer.cameras, [testTile]),
      throwsA(isA<OverpassException>()),
    );
    rig.wait(const Duration(seconds: 31));
    await c.fetch(OsmLayer.cameras, [testTile]);
    expect(calls, 2);
  });

  test(
    'Pausen zählen nicht doppelt: tot ersetzt die Zeitüberschreitungs-Pause',
    () async {
      rig.mode['main.test'] = 'silent';
      await rig.fetch();
      // Nach 31 s wäre die alte Pause vorbei; der Endpunkt ruht aber 10 Minuten (tot), nicht beides.
      rig.wait(const Duration(seconds: 31));
      await rig.fetch();
      expect(rig.calls, ['second.test']);
      rig.wait(const Duration(minutes: 10));
      rig.mode['main.test'] = 'ok';
      await rig.fetch();
      expect(rig.calls, ['main.test']);
    },
  );
}
