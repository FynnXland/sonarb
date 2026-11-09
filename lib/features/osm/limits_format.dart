import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/geo/geo.dart';
import 'osm_tile.dart';

/// Offline-Paket mit Tempolimit-Wegen: eine Datei je Bundesland, nach Zellen gegliedert.
///
/// Die Zellen sind dieselben 0,05°-Kacheln wie im Overpass-Cache ([fineTilesPerDegree]); der Reader
/// liefert pro Zelle die Wege so, wie `speedLimitAt` sie braucht. Aufbau:
///
///     "SBLP" | Format u8 | Stand u32 (JJJJMMTT) | Raster u8 | Kennung (u16 Länge + UTF-8) | Zellen u32
///     je Zelle: iy i32 | ix i32 | Offset u32 | Länge u32 | Flags u8      (aufsteigend nach iy, ix)
///     je Zelle ein Block, roh deflatet (Offset ab Ende des Index)
///
/// Block: Anzahl Wege (Varint), je Weg: Flags u8 (Bit 0–1 Einbahn 0/1/2 = beidseitig/vor/gegen, Bit 2
/// Nebenstraße, Bit 3 Limit rückwärts weicht ab), Limit vorwärts u8 (0 = keines), ggf. Limit rückwärts u8,
/// Punktzahl − 2 (Varint), Punkte als Zickzack-Varints in 1e-7° (der erste ab dem Zellenursprung,
/// dann je ab dem Vorgänger). Raster 1 = 1e-7°, die Auflösung von OSM selbst (verlustfrei); größere
/// Raster (10 = 1e-6°, 100 = 1e-5°) runden alle Punkte auf ein Vielfaches und sparen Platz.
const String limitPackageMagic = 'SBLP';
const int limitPackageFormat = 1;

/// Einheit der Koordinaten im Paket: 1e-7 Grad.
const double _unit = 1e7;

/// Flag eines Zelleneintrags: die Zelle liegt ganz im Gebiet des Pakets (keine Randzelle).
const int cellComplete = 1;

class LimitCellEntry {
  const LimitCellEntry(this.offset, this.length, this.flags);

  final int offset;
  final int length;
  final int flags;

  bool get complete => flags & cellComplete != 0;
}

/// Weg in Paketauflösung (ganze Zahlen in 1e-7°), wie ihn der Generator schreibt.
class RawWay {
  RawWay({
    required this.lat,
    required this.lon,
    this.forward,
    this.backward,
    this.oneway = 0,
    this.minor = false,
  });

  final List<int> lat;
  final List<int> lon;
  final int? forward;
  final int? backward;
  final int oneway;
  final bool minor;
}

/// Gelesener Weg samt Kennzeichen Nebenstraße (nur bei langsamer Fahrt nötig).
class LimitWay {
  const LimitWay(this.way, this.minor);

  final SpeedWay way;
  final bool minor;
}

/// Ursprung der Zelle ([iy], [ix]) in Paketeinheiten.
int _origin(int index, int grid) =>
    index * (500000 ~/ grid); // 0,05° in Rasterschritten

Uint8List encodeCell(int iy, int ix, List<RawWay> ways, {int grid = 1}) {
  final out = BytesBuilder(copy: false);
  void varint(int v) {
    while (v >= 0x80) {
      out.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  void zigzag(int v) => varint((v << 1) ^ (v >> 63));
  int limit(int? v) => v == null ? 0 : v.clamp(1, 255);

  varint(ways.length);
  for (final w in ways) {
    final differs = limit(w.forward) != limit(w.backward);
    final oneway = switch (w.oneway) {
      1 => 1,
      -1 => 2,
      _ => 0,
    };
    out.addByte(oneway | (w.minor ? 4 : 0) | (differs ? 8 : 0));
    out.addByte(limit(w.forward));
    if (differs) out.addByte(limit(w.backward));
    varint(w.lat.length - 2);
    var lat = _origin(iy, grid), lon = _origin(ix, grid);
    for (var i = 0; i < w.lat.length; i++) {
      final la = (w.lat[i] / grid).round(), lo = (w.lon[i] / grid).round();
      zigzag(la - lat);
      zigzag(lo - lon);
      lat = la;
      lon = lo;
    }
  }
  return ZLibEncoder(raw: true, level: 9).convert(out.takeBytes()) as Uint8List;
}

List<LimitWay> decodeCell(int iy, int ix, List<int> block, {int grid = 1}) {
  final data = Uint8List.fromList(ZLibDecoder(raw: true).convert(block));
  var pos = 0;
  int byte() => data[pos++];
  int varint() {
    var shift = 0, v = 0;
    while (true) {
      final b = byte();
      v |= (b & 0x7f) << shift;
      if (b < 0x80) return v;
      shift += 7;
    }
  }

  int zigzag() {
    final v = varint();
    return (v >> 1) ^ -(v & 1);
  }

  final ways = <LimitWay>[];
  for (var n = varint(); n > 0; n--) {
    final flags = byte();
    final forward = byte();
    final backward = flags & 8 != 0 ? byte() : forward;
    final count = varint() + 2;
    var lat = _origin(iy, grid), lon = _origin(ix, grid);
    final points = <GeoPoint>[];
    for (var i = 0; i < count; i++) {
      lat += zigzag();
      lon += zigzag();
      points.add(GeoPoint(lat * grid / _unit, lon * grid / _unit));
    }
    ways.add(
      LimitWay(
        SpeedWay(
          points: points,
          forward: forward == 0 ? null : forward,
          backward: backward == 0 ? null : backward,
          oneway: const [0, 1, -1][flags & 3],
          // Das Paket kennt nur Haupt- und Nebenstraße, keine Namen.
          minor: flags & 4 != 0,
        ),
        flags & 4 != 0,
      ),
    );
  }
  return ways;
}

/// Setzt eine Paketdatei aus fertig kodierten Zellblöcken zusammen.
Uint8List buildPackage({
  required String id,
  required int date,
  required Map<(int, int), (Uint8List, int)> cells,
  int grid = 1,
}) {
  final keys = cells.keys.toList()
    ..sort(
      (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
    );
  final name = utf8.encode(id);
  final head = ByteData(12 + name.length + 4 + keys.length * 17);
  var p = 0;
  for (final c in limitPackageMagic.codeUnits) {
    head.setUint8(p++, c);
  }
  head.setUint8(p++, limitPackageFormat);
  head.setUint32(p, date);
  p += 4;
  head.setUint8(p++, grid);
  head.setUint16(p, name.length);
  p += 2;
  for (final b in name) {
    head.setUint8(p++, b);
  }
  head.setUint32(p, keys.length);
  p += 4;
  var offset = 0;
  for (final k in keys) {
    final (block, flags) = cells[k]!;
    head.setInt32(p, k.$1);
    head.setInt32(p + 4, k.$2);
    head.setUint32(p + 8, offset);
    head.setUint32(p + 12, block.length);
    head.setUint8(p + 16, flags);
    p += 17;
    offset += block.length;
  }
  final out = BytesBuilder(copy: false)..add(head.buffer.asUint8List());
  for (final k in keys) {
    out.add(cells[k]!.$1);
  }
  return out.takeBytes();
}

/// Geöffnetes Paket: Kopf und Index sind im Speicher, die Zellen werden einzeln gelesen.
class LimitPackage {
  LimitPackage._(
    this.file,
    this.id,
    this.date,
    this.grid,
    this._index,
    this._dataStart,
  );

  final File file;
  final String id;

  /// Stand der Karten-Daten (JJJJMMTT).
  final int date;

  /// Rasterweite der Punkte in 1e-7°.
  final int grid;
  final Map<(int, int), LimitCellEntry> _index;
  final int _dataStart;

  /// Liest Kopf und Index. Wirft [FormatException], wenn die Datei kein gültiges Paket ist.
  static Future<LimitPackage> open(File file) async {
    final raf = await file.open();
    try {
      final size = await raf.length();
      Future<ByteData> read(int n) async {
        final b = await raf.read(n);
        if (b.length != n) throw const FormatException('Paket zu kurz');
        return ByteData.sublistView(b);
      }

      final head = await read(12);
      if (String.fromCharCodes([
            for (var i = 0; i < 4; i++) head.getUint8(i),
          ]) !=
          limitPackageMagic) {
        throw const FormatException('kein Tempolimit-Paket');
      }
      if (head.getUint8(4) != limitPackageFormat) {
        throw FormatException('Paketformat ${head.getUint8(4)} unbekannt');
      }
      final date = head.getUint32(5);
      final grid = head.getUint8(9);
      if (grid < 1) throw const FormatException('Raster ungültig');
      final nameLength = head.getUint16(10);
      final nameBytes = (await read(nameLength)).buffer.asUint8List();
      final count = (await read(4)).getUint32(0);
      if (count > 1000000) throw const FormatException('Index unplausibel');
      final table = await read(count * 17);
      final start = 12 + nameLength + 4 + count * 17;
      final index = <(int, int), LimitCellEntry>{};
      for (var i = 0; i < count; i++) {
        final o = i * 17;
        final entry = LimitCellEntry(
          table.getUint32(o + 8),
          table.getUint32(o + 12),
          table.getUint8(o + 16),
        );
        if (start + entry.offset + entry.length > size) {
          throw const FormatException('Zelle liegt hinter dem Dateiende');
        }
        index[(table.getInt32(o), table.getInt32(o + 4))] = entry;
      }
      return LimitPackage._(
        file,
        utf8.decode(nameBytes),
        date,
        grid,
        index,
        start,
      );
    } finally {
      await raf.close();
    }
  }

  int get cellCount => _index.length;

  Iterable<TileId> get cells => [
    for (final k in _index.keys) TileId(k.$2, k.$1, fineTilesPerDegree),
  ];

  /// Hat das Paket diese Zelle (auch eine ohne Wege mit Limit)?
  bool hasCell(TileId id) => _index.containsKey((id.iy, id.ix));

  /// Liegt die Zelle ganz im Gebiet des Pakets?
  bool isComplete(TileId id) => _index[(id.iy, id.ix)]?.complete ?? false;

  /// Die Wege der Zelle; leer, wenn das Paket sie nicht kennt.
  Future<List<LimitWay>> readCell(TileId id) async {
    final entry = _index[(id.iy, id.ix)];
    if (entry == null || entry.length == 0) return const [];
    final raf = await file.open();
    try {
      await raf.setPosition(_dataStart + entry.offset);
      final block = await raf.read(entry.length);
      if (block.length != entry.length) {
        throw const FormatException('Zelle abgeschnitten');
      }
      return decodeCell(id.iy, id.ix, block, grid: grid);
    } finally {
      await raf.close();
    }
  }

  /// Umriss aller Zellen des Pakets.
  GeoBounds? get bounds {
    GeoBounds? b;
    for (final id in cells) {
      final c = id.bounds;
      b = b == null
          ? c
          : GeoBounds(
              south: b.south < c.south ? b.south : c.south,
              west: b.west < c.west ? b.west : c.west,
              north: b.north > c.north ? b.north : c.north,
              east: b.east > c.east ? b.east : c.east,
            );
    }
    return b;
  }
}
