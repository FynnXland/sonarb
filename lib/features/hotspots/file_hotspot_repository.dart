import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/contracts/hotspot_repository.dart';
import '../../core/geo/geo.dart';
import 'hotspot_codec.dart';
import 'hotspot_file_store.dart';

/// Doppel-Tap-Schutz: gleiche Art, näher als dieser Wert und jünger als das Zeitfenster.
const double doubleTapRadiusMeters = 50;
const Duration doubleTapWindow = Duration(seconds: 10);

/// Import: gleiche Art näher als dieser Wert gilt als Duplikat.
const double importDuplicateMeters = 25;

/// Hotspots im Speicher, persistiert in `dataDir/hotspots.json`.
/// Änderungen wirken sofort auf die Liste; das Schreiben läuft serialisiert im Hintergrund.
class FileHotspotRepository implements HotspotRepository {
  FileHotspotRepository._(
    this._store,
    List<Hotspot> items,
    this._clock,
    this._onError,
  ) : _items = items;

  static Future<FileHotspotRepository> open(
    Directory dataDir, {
    DateTime Function()? clock,
    HotspotErrorLogger? onError,
  }) async {
    final logger = onError ?? defaultHotspotLogger;
    final store = HotspotFileStore(dataDir, onError: logger);
    final items = await store.load();
    return FileHotspotRepository._(store, items, clock ?? DateTime.now, logger);
  }

  final HotspotFileStore _store;
  final DateTime Function() _clock;
  final HotspotErrorLogger _onError;
  final List<Hotspot> _items;
  final _changes = StreamController<List<Hotspot>>.broadcast();
  static const _uuid = Uuid();

  String? _lastAddedId;
  bool _dirty = false;
  bool _writing = false;
  Future<void> _writeDone = Future.value();

  List<Hotspot> get _snapshot => List.unmodifiable(_items);

  void _changed() {
    if (!_changes.isClosed) _changes.add(_snapshot);
    _dirty = true;
    if (!_writing) {
      _writing = true;
      _writeDone = _writeLoop();
    }
  }

  /// Schreibt, bis nichts mehr aussteht; Änderungen während eines Schreibvorgangs
  /// werden zusammengefasst und danach mit dem neuesten Stand geschrieben.
  Future<void> _writeLoop() async {
    try {
      while (_dirty) {
        _dirty = false;
        try {
          await _store.write(List.of(_items));
        } catch (e, st) {
          _onError('hotspots.json konnte nicht geschrieben werden', e, st);
        }
      }
    } finally {
      _writing = false;
    }
  }

  /// Wartet, bis alle bisherigen Änderungen geschrieben (oder als Fehler geloggt) sind.
  @override
  Future<void> flush() => _writeDone;

  /// Schreibt noch Ausstehendes und schließt den Stream.
  @override
  Future<void> dispose() async {
    await flush();
    await _changes.close();
  }

  @override
  Stream<List<Hotspot>> watch() => Stream.multi((c) {
    c.add(_snapshot);
    final sub = _changes.stream.listen(c.add);
    c.onCancel = sub.cancel;
  }, isBroadcast: true);

  @override
  Future<List<Hotspot>> all() async => _snapshot;

  @override
  Future<Hotspot> addAt(
    GeoPoint position, {
    double? headingDeg,
    HotspotKind kind = HotspotKind.mobileCamera,
  }) async {
    final now = _clock();
    for (final h in _items) {
      final age = now.difference(h.createdAt);
      if (h.kind == kind &&
          !age.isNegative &&
          age < doubleTapWindow &&
          distanceMeters(h.position, position) < doubleTapRadiusMeters) {
        return h;
      }
    }
    final h = Hotspot(
      id: _uuid.v4(),
      position: position,
      createdAt: now,
      kind: kind,
      headingDeg: headingDeg == null ? null : normalizeDegrees(headingDeg),
    );
    _items.insert(0, h);
    _lastAddedId = h.id;
    _changed();
    return h;
  }

  @override
  Future<void> update(Hotspot hotspot) async {
    final i = _items.indexWhere((e) => e.id == hotspot.id);
    if (i < 0) return;
    _items[i] = hotspot;
    _changed();
    await flush();
  }

  @override
  Future<void> remove(String id) async {
    final before = _items.length;
    _items.removeWhere((e) => e.id == id);
    if (_items.length == before) return;
    if (_lastAddedId == id) _lastAddedId = null;
    _changed();
    await flush();
  }

  /// Entfernt den zuletzt per [addAt] angelegten Hotspot; ist er schon weg, passiert nichts.
  @override
  Future<void> undoLast() async {
    final id = _lastAddedId;
    if (id == null) return;
    _lastAddedId = null;
    await remove(id);
  }

  @override
  Future<String> exportJson() async =>
      encodeHotspotDocument(_items, _clock(), pretty: true);

  @override
  Future<HotspotImportResult> importJson(String json) async {
    final entries = parseHotspotDocument(json);
    final now = _clock();
    final ids = {for (final h in _items) h.id};
    final merged = List.of(_items);
    var added = 0, skipped = 0, invalid = 0;

    for (final raw in entries) {
      final h = hotspotFromJson(raw, newId: _uuid.v4, now: now);
      if (h == null) {
        invalid++;
      } else if (ids.contains(h.id) || _hasNeighbour(merged, h)) {
        skipped++;
      } else {
        ids.add(h.id);
        merged.add(h);
        added++;
      }
    }

    if (added > 0) {
      _items
        ..clear()
        ..addAll(sortNewestFirst(merged));
      _changed();
      await flush();
    }
    return HotspotImportResult(
      added: added,
      skippedDuplicates: skipped,
      invalid: invalid,
    );
  }

  static bool _hasNeighbour(List<Hotspot> list, Hotspot h) {
    for (final o in list) {
      if (o.kind != h.kind) continue;
      // Grobfilter (~55 m in Breite), spart die Haversine-Rechnung bei großen Listen.
      if ((o.position.lat - h.position.lat).abs() > 0.0005) continue;
      if (distanceMeters(o.position, h.position) < importDuplicateMeters) {
        return true;
      }
    }
    return false;
  }
}
