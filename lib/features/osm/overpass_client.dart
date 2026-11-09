import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../core/geo/geo.dart';
import 'osm_country.dart';
import 'osm_details.dart';
import 'osm_layer.dart';
import 'osm_log.dart';
import 'osm_parser.dart';
import 'osm_tile.dart';

/// Nur ASCII: `dart:io` lehnt andere Zeichen in Kopfzeilen ab (FormatException), dann scheitert
/// jede Anfrage schon vor dem Senden.
const String overpassUserAgent =
    'Sonarb/1.0 (driver assistance app for Android; de.fynn.handy.sonarb)';

/// Öffentliche Instanzen laut OSM-Wiki (Stand 2026): die FOSSGIS-Hauptinstanz und Private.coffee
/// (vormals overpass.kumi.systems).
const List<String> defaultOverpassEndpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

/// Gründe, warum eine Abfrage scheitert. Jeder ist ein kurzer deutscher Satzanfang und passt vor
/// „, Daten unvollständig“ in `SourceResult.error`.
abstract final class OverpassReason {
  /// Kein Netz, Server nicht erreichbar, unerwarteter Status.
  static const String unreachable = 'Overpass nicht erreichbar';

  /// 429/502/503/504/406 oder `runtime error`: der Server hat gerade keine Kapazität.
  static const String overloaded = 'Overpass überlastet';

  /// Keine Antwort innerhalb der Frist.
  static const String silent = 'Overpass antwortet nicht';

  /// Die Verbindung riss mitten in der Antwort ab (Funkloch, abgeschnittenes JSON).
  static const String aborted = 'Verbindung abgebrochen';

  /// Eine Antwort kam, ist aber kein brauchbares JSON (HTML- oder Textseite, falsche Form).
  static const String unusable = 'Antwort unbrauchbar';
}

/// Abfrage gescheitert. [reason] ist einer der [OverpassReason]-Werte.
class OverpassException implements Exception {
  const OverpassException(this.reason, {this.retryAfter});

  /// Kurzer Grund für die Anzeige.
  final String reason;

  /// Gesetzt bei vorübergehenden Fehlern (Überlast, Abbruch, unbrauchbare Antwort): so lange lohnt kein
  /// neuer Versuch. Null = Warten bringt nichts (kein Netz, falsche Antwortform).
  final Duration? retryAfter;

  @override
  String toString() => 'OverpassException($reason)';
}

/// Die Antwort ist JSON, aber nicht die erwartete Form.
class _BadShape implements Exception {
  const _BadShape();

  @override
  String toString() => 'Antwort ohne "elements"';
}

/// Holt eine Kachel-Schicht von Overpass, mit Ausweich-Endpunkt und Pause bei Überlast.
class OverpassClient {
  OverpassClient({
    required this.client,
    this.endpoints = defaultOverpassEndpoints,
    DateTime Function()? now,
    this.deadPause = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final http.Client client;
  final List<String> endpoints;
  final DateTime Function() _now;

  /// So lange wird ein Endpunkt übersprungen, der nicht antwortet, während ein anderer antwortet.
  final Duration deadPause;

  /// So lange gilt die Antwort eines anderen Endpunkts als Beweis, dass das Netz geht.
  static const Duration evidenceWindow = Duration(minutes: 10);

  /// Pausen nach aufeinanderfolgender Überlast desselben Endpunkts (auch Zeitüberschreitung); die Wiki verlangt mindestens 30 s.
  static const List<Duration> backoffSteps = [
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
  ];
  static const Duration maxRetryAfter = Duration(minutes: 5);

  /// 429/406 (zu viele Anfragen), 502/503/504 (alle Worker belegt): der Server verlangt Abstand.
  static const Set<int> _overloadStatus = {406, 429, 502, 503, 504};

  /// Ab dieser Größe wird die Antwort in einem Isolate zerlegt, damit die Oberfläche nicht ruckelt.
  static const int _isolateThreshold = 200 * 1024;

  final Map<String, DateTime> _pausedUntil = {};
  final Map<String, DateTime> _deadUntil = {};
  final Map<String, DateTime> _lastAnswer = {};
  final Map<String, int> _strikes = {};

  /// Holt [tiles] in einer Anfrage über ihre gemeinsame Hülle und teilt die Antwort auf die Kacheln auf.
  Future<Map<TileId, TileData>> fetch(OsmLayer layer, List<TileId> tiles) =>
      _run(
        buildLayerQuery(layer, _hull(tiles)),
        layer.httpTimeout,
        '${layer.name} ${[for (final t in tiles) t.key]}',
        (body) => _parse(body, layer, tiles),
      );

  /// Die Blitzer ganz Deutschlands in einer Anfrage, einmal ausgewertet.
  Future<CountryData> fetchCountry({
    Duration timeout = const Duration(seconds: 300),
  }) => _run(
    buildCountryQuery(),
    timeout,
    'Deutschland',
    (body) => _parseCountry(body, _now()),
  );

  /// Sendet [query] an die Endpunkte der Reihe nach (Pause, Abbruch, Müllantwort: nächster Endpunkt)
  /// und gibt das Ergebnis von [parse] zurück. Fehler siehe [OverpassReason].
  ///
  /// Ein Endpunkt, der nicht antwortet (Zeitüberschreitung, Verbindung scheitert), während ein anderer
  /// kürzlich geantwortet hat (auch mit Überlast), gilt [deadPause] lang als tot und wird übersprungen.
  /// Ein toter Endpunkt, der früher einmal geantwortet hat, kommt als Notnagel wieder dran, wenn sonst
  /// keiner antwortet (er könnte der einzige sein, der geht); einer, der nie geantwortet hat, erst nach der Pause.
  Future<T> _run<T>(
    String query,
    Duration timeout,
    String label,
    Future<T> Function(String body) parse,
  ) async {
    var reason = OverpassReason.unreachable;
    var transient = false;
    var answered = false; // irgendein Endpunkt hat geantwortet: das Netz geht
    final silent =
        <
          String,
          bool
        >{}; // Endpunkt ohne Antwort → war es eine Zeitüberschreitung?
    final deadAtStart = {
      for (final e in endpoints)
        if (_deadLeft(e) != null) e,
    };
    // Notnagel: tote Endpunkte, die früher einmal geantwortet haben.
    final fallback = {
      for (final e in deadAtStart)
        if (_lastAnswer.containsKey(e)) e,
    };
    for (var pass = 0; pass < 2; pass++) {
      // Zweiter Durchgang nur, wenn niemand sonst geantwortet hat.
      if (pass == 1 && (answered || fallback.isEmpty)) break;
      for (final endpoint in endpoints) {
        if (deadAtStart.contains(endpoint) &&
            (pass == 0 || !fallback.contains(endpoint))) {
          continue;
        }
        if (pass == 1 && !deadAtStart.contains(endpoint)) continue;
        if (_pauseLeft(endpoint) != null) {
          reason = OverpassReason.overloaded;
          transient = true;
          continue;
        }
        final http.Response response;
        try {
          response = await client
              .post(
                Uri.parse(endpoint),
                headers: {
                  'User-Agent': overpassUserAgent,
                  'Accept': 'application/json',
                  // Overpass komprimiert: die Antworten schrumpfen auf rund ein Fünftel.
                  'Accept-Encoding': 'gzip',
                },
                body: {'data': query},
              )
              .timeout(timeout);
        } on TimeoutException {
          reason = OverpassReason.silent;
          transient = true;
          silent[endpoint] = true;
          continue;
        } catch (e) {
          // `http` meldet einen Abbruch während der Übertragung (auch Android) als ClientException,
          // ein abgeschnittener gzip-Strom als FormatException.
          if (_isAborted(e)) {
            reason = OverpassReason.aborted;
            transient = true;
            answered = true; // die Verbindung stand
            _lastAnswer[endpoint] = _now();
          } else {
            reason = OverpassReason.unreachable;
            silent[endpoint] = false;
          }
          osmLog('$label $endpoint: $reason ($e)');
          continue;
        }
        answered = true;
        _lastAnswer[endpoint] = _now();
        if (_overloadStatus.contains(response.statusCode)) {
          reason = OverpassReason.overloaded;
          transient = true;
          _pause(endpoint, response.headers['retry-after']);
          continue;
        }
        if (response.statusCode != 200) {
          reason = OverpassReason.unreachable;
          osmLog('$label $endpoint: Status ${response.statusCode}');
          continue;
        }
        // Overpass-JSON ist immer UTF-8, egal was der Kopf sagt; kaputte Bytes werfen hier nicht.
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (_hasRuntimeError(body)) {
          reason = OverpassReason.overloaded;
          continue;
        }
        try {
          final data = await parse(body);
          _strikes.remove(endpoint);
          _deadUntil.remove(endpoint);
          _noteSilence(silent);
          return data;
        } on FormatException catch (e) {
          // Beginnt wie JSON, ist aber unvollständig: abgeschnitten. Sonst Text- oder HTML-Seite.
          reason = body.trimLeft().startsWith('{')
              ? OverpassReason.aborted
              : OverpassReason.unusable;
          transient = true;
          osmLog(
            '$label: ${e.message}; '
            '${response.bodyBytes.length} Bytes, ${response.headers['content-type']}, '
            'Anfang: ${_snippet(body)}',
          );
        } catch (e) {
          // Gültiges JSON in unerwarteter Form (kein "elements"): Warten ändert daran nichts.
          reason = OverpassReason.unusable;
          osmLog(
            '$label: $e; '
            'Anfang: ${_snippet(body)}',
          );
        }
      }
    }
    _noteSilence(silent);
    // Bei Überlast lohnt ein neuer Versuch, sobald der erste Endpunkt wieder frei ist (null = kein Grund zu warten).
    Duration? soonest;
    if (transient) {
      soonest = Duration.zero;
      final lefts = [for (final e in endpoints) _waitLeft(e)];
      if (lefts.every((l) => l != null)) {
        soonest = lefts.reduce((a, b) => a! < b! ? a : b);
      }
    }
    throw OverpassException(reason, retryAfter: soonest);
  }

  /// Endpunkte, die in diesem Lauf nicht antworteten: Hat ein anderer in den letzten [evidenceWindow]
  /// geantwortet, liegt es am Endpunkt und er ruht [deadPause] lang (statt bei jedem Versuch die ganze
  /// Frist zu kosten). Sonst ist vermutlich das Netz weg: kein Urteil über den Endpunkt, eine
  /// Zeitüberschreitung bekommt die übliche kurze Pause.
  void _noteSilence(Map<String, bool> silent) {
    final now = _now();
    for (final e in silent.entries) {
      final othersAnswered = _lastAnswer.entries.any(
        (o) => o.key != e.key && now.difference(o.value) <= evidenceWindow,
      );
      if (othersAnswered && deadPause > Duration.zero) {
        _deadUntil[e.key] = now.add(deadPause);
        _pausedUntil.remove(e.key);
        _strikes.remove(e.key);
      } else if (e.value) {
        _pause(e.key, null);
      }
    }
  }

  Duration? _pauseLeft(String endpoint) {
    final until = _pausedUntil[endpoint];
    if (until == null) return null;
    final left = until.difference(_now());
    if (left > Duration.zero) return left;
    _pausedUntil.remove(endpoint);
    return null;
  }

  Duration? _deadLeft(String endpoint) {
    final until = _deadUntil[endpoint];
    if (until == null) return null;
    final left = until.difference(_now());
    if (left > Duration.zero) return left;
    _deadUntil.remove(endpoint);
    return null;
  }

  /// Wie lange [endpoint] noch ruht (Überlast oder tot), null = frei.
  Duration? _waitLeft(String endpoint) {
    final a = _pauseLeft(endpoint), b = _deadLeft(endpoint);
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }

  /// Setzt die Pause für [endpoint]: `Retry-After` (Sekunden), sonst 30/60/120 s.
  Duration _pause(String endpoint, String? retryAfter) {
    final running = _pauseLeft(endpoint);
    if (running != null) return running; // parallele Antwort derselben Überlast
    final strikes = _strikes[endpoint] ?? 0;
    _strikes[endpoint] = strikes + 1;
    final seconds = int.tryParse(retryAfter?.trim() ?? '');
    var pause = seconds != null && seconds > 0
        ? Duration(seconds: seconds)
        : backoffSteps[strikes.clamp(0, backoffSteps.length - 1)];
    if (pause > maxRetryAfter) pause = maxRetryAfter;
    _pausedUntil[endpoint] = _now().add(pause);
    return pause;
  }

  static bool _isAborted(Object e) {
    final t = e.toString().toLowerCase();
    return t.contains('connection closed') ||
        t.contains('connection reset') ||
        t.contains('connection terminated') ||
        t.contains('broken pipe') ||
        t.contains('connection abort') ||
        t.contains('filter error') ||
        t.contains('unexpected end');
  }

  static String _snippet(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 80 ? '${t.substring(0, 80)}…' : t;
  }

  /// Overpass meldet Zeit-/Speichergrenzen mit Status 200 und einer „remark“ mit „runtime error“.
  static bool _hasRuntimeError(String body) {
    final i = body.indexOf('"remark"');
    return i >= 0 && body.indexOf('runtime error', i) >= 0;
  }

  Future<Map<TileId, TileData>> _parse(
    String body,
    OsmLayer layer,
    List<TileId> tiles,
  ) async {
    final now = _now();
    final withWays = layer.hasWays;
    Map<TileId, TileData> run() {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic> || json['elements'] is! List) {
        throw const _BadShape();
      }
      final parsed = parseAll(json, withWays: withWays);
      return {
        for (final t in tiles)
          t: tileDataOf(
            parsed,
            t,
            now,
            detailVersion: withWays ? wayDetailVersion : pointDetailVersion,
          ),
      };
    }

    return body.length < _isolateThreshold ? run() : Isolate.run(run);
  }

  Future<CountryData> _parseCountry(String body, DateTime now) {
    CountryData run() {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic> || json['elements'] is! List) {
        throw const _BadShape();
      }
      return CountryData.fromParsed(parseAll(json, withWays: false), now);
    }

    return body.length < _isolateThreshold
        ? Future.value(run())
        : Isolate.run(run);
  }

  static GeoBounds _hull(List<TileId> tiles) {
    final b = [for (final t in tiles) t.bounds];
    return GeoBounds(
      south: b.map((e) => e.south).reduce(math.min),
      west: b.map((e) => e.west).reduce(math.min),
      north: b.map((e) => e.north).reduce(math.max),
      east: b.map((e) => e.east).reduce(math.max),
    );
  }
}
