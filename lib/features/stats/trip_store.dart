import 'dart:convert';
import 'dart:io';

import 'trip_summary.dart';
import 'trip_trace.dart';

/// Höchstens so viele Fahrten bleiben gespeichert, unabhängig von der Aufbewahrung.
const int maxStoredTrips = 1000;

/// Gespeicherte Fahrten, nur auf dem Gerät.
abstract interface class TripStore {
  /// Alle Fahrten, neueste zuerst.
  Future<List<TripSummary>> load();

  /// Ersetzt den ganzen Bestand. Verläufe von Fahrten, die nicht mehr darin sind, fallen weg.
  Future<void> save(List<TripSummary> trips);

  /// Tempoverlauf der Fahrt [id]; null, wenn es keinen gibt (ältere Fahrten).
  Future<TripTrace?> loadTrace(String id);

  Future<void> saveTrace(String id, TripTrace trace);
}

/// Nur IDs aus diesen Zeichen werden zu Dateinamen.
final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Behält Fahrten, die nach [now] − [keep] begonnen haben, höchstens [maxStoredTrips],
/// neueste zuerst.
List<TripSummary> retain(
  Iterable<TripSummary> trips, {
  required DateTime now,
  required Duration keep,
}) {
  final from = now.subtract(keep);
  final kept = [
    for (final t in trips)
      if (!t.start.isBefore(from)) t,
  ]..sort((a, b) => b.start.compareTo(a.start));
  return kept.length > maxStoredTrips ? kept.sublist(0, maxStoredTrips) : kept;
}

/// JSON-Datei `trips.json` im Ordner, den [directory] liefert. Der Ordner wird erst beim
/// ersten Zugriff ermittelt; fehlt er (Tests ohne Plattform), wirft der Zugriff.
class FileTripStore implements TripStore {
  FileTripStore(this._directory);

  final Future<Directory> Function() _directory;
  File? _file;

  static const _version = 1;

  Future<File> _resolve() async {
    final known = _file;
    if (known != null) return known;
    final dir = await _directory();
    await dir.create(recursive: true);
    return _file = File('${dir.path}${Platform.pathSeparator}trips.json');
  }

  Future<Directory> _traces() async {
    final file = await _resolve();
    return Directory('${file.parent.path}${Platform.pathSeparator}traces');
  }

  Future<File?> _traceFile(String id) async {
    if (!_safeId.hasMatch(id)) return null;
    final dir = await _traces();
    return File('${dir.path}${Platform.pathSeparator}$id.json');
  }

  @override
  Future<TripTrace?> loadTrace(String id) async {
    final file = await _traceFile(id);
    if (file == null || !await file.exists()) return null;
    try {
      return TripTrace.fromJson(jsonDecode(await file.readAsString()));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveTrace(String id, TripTrace trace) async {
    final file = await _traceFile(id);
    if (file == null) return;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(trace.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  /// Löscht Verläufe ohne Fahrt in [trips].
  Future<void> _prune(List<TripSummary> trips) async {
    final dir = await _traces();
    if (!await dir.exists()) return;
    final keep = {for (final t in trips) '${t.id}.json'};
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (!keep.contains(name)) await e.delete();
    }
  }

  @override
  Future<List<TripSummary>> load() async {
    final file = await _resolve();
    if (!await file.exists()) return const [];
    final Object? raw;
    try {
      raw = jsonDecode(await file.readAsString());
    } on FormatException {
      return const [];
    }
    final list = raw is Map ? raw['trips'] : null;
    if (list is! List) return const [];
    return [for (final e in list) ?TripSummary.fromJson(e)]
      ..sort((a, b) => b.start.compareTo(a.start));
  }

  @override
  Future<void> save(List<TripSummary> trips) async {
    final file = await _resolve();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': _version,
        'trips': [for (final t in trips) t.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(file.path);
    await _prune(trips);
  }
}

/// Für Tests und als Ersatz, wenn kein Speicher da ist.
class MemoryTripStore implements TripStore {
  MemoryTripStore([List<TripSummary> trips = const []])
    : trips = List.of(trips);

  List<TripSummary> trips;
  final traces = <String, TripTrace>{};
  int saves = 0;

  @override
  Future<List<TripSummary>> load() async => List.of(trips);

  @override
  Future<void> save(List<TripSummary> trips) async {
    saves++;
    this.trips = List.of(trips);
    final ids = {for (final t in trips) t.id};
    traces.removeWhere((id, _) => !ids.contains(id));
  }

  @override
  Future<TripTrace?> loadTrace(String id) async => traces[id];

  @override
  Future<void> saveTrace(String id, TripTrace trace) async {
    traces[id] = trace;
  }
}
