import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../app/services.dart';
import '../../core/contracts/warning_engine.dart';
import '../../core/model/position_fix.dart';
import '../../core/model/road_limit.dart';
import 'trip_recorder.dart';
import 'trip_store.dart';
import 'trip_summary.dart';
import 'trip_trace.dart';

/// Wählbare Aufbewahrung in Tagen.
const statsKeepChoices = <int>[30, 90, 365];

/// Aufzeichnung an oder aus und wie lange Fahrten bleiben. Gespeichert in SharedPreferences.
class StatsSettings {
  const StatsSettings({this.enabled = true, this.keepDays = 365});

  final bool enabled;
  final int keepDays;

  Duration get keep => Duration(days: keepDays);
}

class StatsSettingsController extends Notifier<StatsSettings> {
  static const _kEnabled = 'stats.enabled';
  static const _kKeep = 'stats.keepDays';

  @override
  StatsSettings build() {
    final p = ref.watch(servicesProvider).prefs;
    final keep = p.getInt(_kKeep);
    return StatsSettings(
      enabled: p.getBool(_kEnabled) ?? true,
      keepDays: statsKeepChoices.contains(keep) ? keep! : 365,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    state = StatsSettings(enabled: enabled, keepDays: state.keepDays);
    await ref.read(servicesProvider).prefs.setBool(_kEnabled, enabled);
  }

  /// Kürzere Aufbewahrung löscht ältere Fahrten sofort.
  Future<void> setKeepDays(int days) async {
    state = StatsSettings(enabled: state.enabled, keepDays: days);
    await ref.read(servicesProvider).prefs.setInt(_kKeep, days);
    await ref.read(tripsProvider.notifier).prune();
  }
}

final statsSettingsProvider =
    NotifierProvider<StatsSettingsController, StatsSettings>(
      StatsSettingsController.new,
    );

/// Uhr für die Aufbewahrung, in Tests ersetzbar.
final statsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Ablage der Fahrten: `stats/trips.json` im App-Speicher.
final tripStoreProvider = Provider<TripStore>(
  (ref) => FileTripStore(() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}stats');
  }),
);

/// Gespeicherte Fahrten, neueste zuerst. Schreibt nacheinander, nie zwei Mal gleichzeitig.
class TripsController extends AsyncNotifier<List<TripSummary>> {
  Future<void> _writes = Future.value();

  TripStore get _store => ref.read(tripStoreProvider);

  List<TripSummary> _retain(Iterable<TripSummary> trips) => retain(
    trips,
    now: ref.read(statsClockProvider)(),
    keep: ref.read(statsSettingsProvider).keep,
  );

  @override
  Future<List<TripSummary>> build() async {
    final loaded = await ref.watch(tripStoreProvider).load();
    // Offen und nicht die laufende Aufzeichnung: Die App wurde während der Fahrt hart beendet.
    final running = ref.read(tripLogProvider).currentId;
    final closed = [
      for (final t in loaded) t.open && t.id != running ? t.closed() : t,
    ];
    final changed = loaded.any((t) => t.open && t.id != running);
    final kept = _retain(closed);
    if (changed || kept.length != loaded.length) await _store.save(kept);
    return kept;
  }

  Future<void> _change(
    List<TripSummary> Function(List<TripSummary>) change, {
    Future<void> Function(List<TripSummary> kept)? then,
  }) {
    final run = _writes.then((_) async {
      final current = await future;
      final next = _retain(change(current));
      await _store.save(next);
      state = AsyncData(next);
      await then?.call(next);
    });
    _writes = run.catchError((Object _) {});
    return run;
  }

  /// Neue Fahrt oder neuer Stand einer schon gespeicherten (gleiche ID), mit ihrem Verlauf.
  /// Der Verlauf wird nach der Zusammenfassung geschrieben und nur, wenn die Fahrt bleibt.
  Future<void> add(TripSummary trip, {TripTrace? trace}) => _change(
    (t) => [
      trip,
      for (final x in t)
        if (x.id != trip.id) x,
    ],
    then: trace == null
        ? null
        : (kept) async {
            if (kept.any((t) => t.id == trip.id)) {
              await _store.saveTrace(trip.id, trace);
            }
          },
  );

  Future<void> delete(String id) => _change(
    (t) => [
      for (final x in t)
        if (x.id != id) x,
    ],
  );

  Future<void> clear() => _change((_) => const []);

  /// Wendet die Aufbewahrung neu an.
  Future<void> prune() => _change((t) => t);
}

final tripsProvider = AsyncNotifierProvider<TripsController, List<TripSummary>>(
  TripsController.new,
  // Ohne Speicher (Tests ohne Plattform) kein Wiederholen im Hintergrund.
  retry: (_, _) => null,
);

/// Tempoverlauf einer gespeicherten Fahrt, erst beim Öffnen gelesen. Null ohne Verlauf.
final tripTraceProvider = FutureProvider.autoDispose.family<TripTrace?, String>(
  (ref, id) async {
    try {
      return await ref.watch(tripStoreProvider).loadTrace(id);
    } catch (e) {
      debugPrint('Verlauf nicht lesbar: $e');
      return null;
    }
  },
);

/// Zwischenspeichern der laufenden Fahrt, damit ein hartes Beenden (Prozess beendet, Akku leer)
/// sie nicht verliert. Jedes Sichern schreibt `trips.json` einmal neu (tmp + rename).
abstract final class TripCheckpoint {
  /// Während der Fahrt höchstens so oft.
  static const every = Duration(minutes: 5);

  /// Steht das Fahrzeug so lange, wird einmal gesichert: Danach endet die Fahrt oft (Parken).
  static const standSeconds = 30.0;
}

/// Verbindet die Überwachung mit der Statistik: Fahrtbeginn, jeder verarbeitete Fix,
/// Fahrtende. Rechnet nur aus Daten, die ohnehin anfallen; fordert nichts an.
class TripLog {
  TripLog(this._ref);

  final Ref _ref;
  TripRecorder? _trip;
  String? _id;
  DateTime? _savedAt;
  bool _standSaved = false;
  RoadLimit _road = const RoadLimit.unknown();
  int? _limitKmh;
  Future<void> _saving = Future.value();

  /// Läuft gerade eine Aufzeichnung?
  bool get recording => _trip != null;

  /// ID der laufenden Aufzeichnung.
  String? get currentId => _trip == null ? null : _id;

  /// Fahrt erkannt. Bei abgeschalteter Aufzeichnung geschieht nichts.
  void started() {
    final on = _ref.read(statsSettingsProvider).enabled;
    _trip = on ? TripRecorder() : null;
    _id = on ? const Uuid().v4() : null;
    _savedAt = null;
    _standSaved = false;
    _road = const RoadLimit.unknown();
    _limitKmh = null;
  }

  /// Jeder Fix der Fahrt, ungedrosselt, auch im Stand. Straße und Limit stammen aus dem
  /// letzten [context]; im Stand fragt niemand neu nach.
  void fix(PositionFix fix) {
    final trip = _trip;
    if (trip == null) return;
    trip.move(fix, road: _road, limitKmh: _limitKmh);
    final standing = trip.standingSeconds >= TripCheckpoint.standSeconds;
    if (trip.standingSeconds == 0) _standSaved = false;
    final savedAt = _savedAt ??= fix.time;
    final due = fix.time.difference(savedAt) >= TripCheckpoint.every;
    if (!due && !(standing && !_standSaved)) return;
    final snapshot = trip.snapshot(_id!);
    if (snapshot == null) return;
    _savedAt = fix.time;
    if (standing) _standSaved = true;
    _save(snapshot, trip.trace());
  }

  /// Ergebnis einer vollen Verarbeitung (Tempolimit, Warnlogik) zu [fix]. Kommt bei Fahrt
  /// mit fast jedem Fix, im Stand selten.
  void context(PositionFix fix, RoadLimit road, WarningUpdate update) {
    _road = road;
    _limitKmh = update.speedLimitKmh ?? road.kmh;
    _trip?.warnings(fix, update);
  }

  Future<void> _save(TripSummary summary, TripTrace? trace) =>
      _saving = _saving.then((_) async {
        try {
          await _ref.read(tripsProvider.notifier).add(summary, trace: trace);
        } catch (e) {
          debugPrint('Fahrt nicht gespeichert: $e');
        }
      });

  /// Fahrt beendet (Stand, Beenden, Zugriff verloren). Speichert sie, wenn sie lang genug war.
  Future<void> ended() async {
    final trip = _trip;
    final id = _id;
    _trip = null;
    _id = null;
    if (trip == null || id == null) return saving;
    // Zu kurz: Dann gab es auch keinen Zwischenstand, es ist nichts zu tun.
    final summary = trip.finish(id);
    return summary == null ? saving : _save(summary, trip.trace());
  }

  /// Endet, wenn alle angestoßenen Schreibvorgänge durch sind.
  Future<void> get saving => _saving;
}

final tripLogProvider = Provider<TripLog>(TripLog.new);
