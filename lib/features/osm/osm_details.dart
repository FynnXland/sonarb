import '../../core/model/alert_point.dart';

/// Version der Angaben in einer Blitzer-Kachel. Ältere Kacheln (ohne Details) laden weiter,
/// gelten aber als veraltet und werden beim nächsten Abruf erneuert.
const int pointDetailVersion = 3;

/// Version der Angaben in einer Tempolimit-Kachel (`limits`, `minorLimits`), unabhängig von den
/// Blitzern: 4 trägt „kein Limit“ (`maxspeed=none`) als `speedWayNoLimit`, 5 dazu Straßenart,
/// Name, ref und Rampen ohne Limit (für die Linie voraus). Ältere Kacheln gelten als veraltet und
/// werden beim nächsten Bedarf erneuert, also nur die Zellen, durch die man fährt; bis dahin
/// bleiben sie in Gebrauch, dann ohne Linie voraus.
const int wayDetailVersion = 5;

const String osmAttribution = '© OpenStreetMap-Mitwirkende, ODbL';

const int _maxTextLength = 200;

const _months = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

const _compass = [
  'Nord',
  'Nordost',
  'Ost',
  'Südost',
  'Süd',
  'Südwest',
  'West',
  'Nordwest',
];

/// Himmelsrichtung in Worten (8 Sektoren), z. B. 45 → „Nordost“.
String compassName(double degrees) =>
    _compass[((degrees % 360 + 360) % 360 / 45 + 0.5).floor() % 8];

/// `2021`, `2021-03` und `2021-03-05` als „2021“, „März 2021“ und „5. März 2021“.
/// Alles andere (Spannen, „~2015“, Freitext) ergibt null und wird nicht angezeigt.
String? formatOsmDate(String? raw) {
  final m = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$')
      .firstMatch(raw?.trim() ?? '');
  if (m == null) return null;
  final year = m.group(1)!;
  final month = int.tryParse(m.group(2) ?? '');
  if (m.group(2) == null) return year;
  if (month == null || month < 1 || month > 12) return null;
  final day = int.tryParse(m.group(3) ?? '');
  if (m.group(3) == null) return '${_months[month - 1]} $year';
  if (day == null || day < 1 || day > 31) return null;
  return '$day. ${_months[month - 1]} $year';
}

String? _text(String? raw) {
  final t = raw?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t == null || t.isEmpty) return null;
  return t.length > _maxTextLength ? '${t.substring(0, _maxTextLength)}…' : t;
}

String? _enforcement(String? raw) {
  if (raw == null) return null;
  final out = <String>[];
  for (final v in raw.split(';')) {
    final t = switch (v.trim()) {
      'maxspeed' => 'Geschwindigkeit',
      'traffic_signals' => 'Rotlicht',
      'average_speed' || 'section_control' => 'Abschnittskontrolle',
      'maxweight' || 'weight' => 'Gewicht',
      'maxheight' => 'Höhe',
      'mindistance' => 'Abstand',
      'access' => 'Einfahrt',
      'noovertaking' || 'no_overtaking' => 'Überholverbot',
      _ => null,
    };
    if (t != null && !out.contains(t)) out.add(t);
  }
  return out.isEmpty ? null : out.join(' und ');
}

/// `3.8`, `3,8 m` → „bis 3,8 m“; alles andere (Spannen, Freitext) ergibt null.
String? _limit(String? raw, String unit) {
  final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(?:m|t)?$')
      .firstMatch(raw?.trim() ?? '');
  return m == null ? null : 'bis ${m.group(1)!.replaceAll('.', ',')} $unit';
}

String? _cameraType(String? raw) => switch (raw?.trim().toLowerCase()) {
  'fixed' => 'fest installiert',
  'mobile' => 'mobil',
  'dome' => 'Kuppelkamera',
  'panning' => 'schwenkbar',
  _ => null,
};

String? _mount(String? raw) => switch (raw?.trim().toLowerCase()) {
  'pole' => 'Mast',
  'wall' => 'Wand',
  'ceiling' => 'Decke',
  'street_lamp' => 'Straßenlaterne',
  'bridge' => 'Brücke',
  'building' => 'Gebäude',
  'gantry' => 'Schilderbrücke',
  _ => null,
};

String? _surveillance(String? raw) => switch (raw?.trim().toLowerCase()) {
  'camera' => 'Kamera',
  'alpr' => 'Kennzeichenerkennung',
  _ => null,
};

/// Richtung in Worten: „Nordost“, „Nord und Süd“, „beide Richtungen“ oder „unbekannt …“.
String directionText(List<double> bearings, {required bool both}) {
  if (bearings.isEmpty) {
    return both ? 'beide Richtungen' : 'unbekannt, warnt in beide Richtungen';
  }
  final names = <String>[];
  for (final b in bearings) {
    final n = compassName(b);
    if (!names.contains(n)) names.add(n);
  }
  return 'in Richtung ${names.join(' und ')}';
}

bool _isBoth(String? direction) => switch (direction?.trim().toLowerCase()) {
  'both' || 'all' || 'forward;backward' || 'backward;forward' => true,
  _ => false,
};

/// Übersetzt die Tags einer Messstelle in kurze deutsche Angaben. Leere und unverständliche
/// Werte entfallen, rohe Tag-Werte werden nie angezeigt.
///
/// [tags] ist die Vereinigung aus Relation und Geräteknoten (Relation zuerst). [road] ist die
/// Straße, an der die Messstelle steht, wenn die Abfrage den Weg schon geliefert hat.
List<PointDetail> buildOsmDetails({
  required Map<String, String> tags,
  required List<double> bearings,
  int? maxSpeed,
  String? road,
}) {
  final out = <PointDetail>[];
  void add(String label, String? value) {
    if (value != null && value.isNotEmpty) out.add(PointDetail(label, value));
  }

  add('Kontrolle', _enforcement(tags['enforcement']));
  add('Erlaubt', maxSpeed == null ? null : '$maxSpeed km/h');
  add('Höchsthöhe', _limit(tags['maxheight'] ?? tags['maxheight:legal'], 'm'));
  add(
    'Höchstgewicht',
    _limit(tags['maxweight'] ?? tags['maxweight:legal'], 't'),
  );
  add('Seit', formatOsmDate(tags['start_date']));
  final direction = tags['direction'] ?? tags['camera:direction'];
  add('Richtung', directionText(bearings, both: _isBoth(direction)));
  add('Straße', _text(road));
  add('Bauart', _cameraType(tags['camera:type']));
  add('Montage', _mount(tags['camera:mount']));
  add('Technik', _surveillance(tags['surveillance:type']));
  add(
    'Zuletzt geprüft',
    formatOsmDate(tags['check_date'] ?? tags['survey:date']),
  );
  add('Betreiber', _text(tags['operator']));
  final name = _text(tags['name']);
  final ref = _text(tags['ref']);
  add('Name', name);
  add('Kennung', ref == name ? null : ref);
  add('Hinweis', _text(tags['note']));
  add('Beschreibung', _text(tags['description']));
  return out;
}

/// Straße als „Frankfurter Allee (B 1)“, nur Name oder nur Kennung; null ohne beides.
String? roadLabel(Map<String, String> wayTags) {
  final name = _text(wayTags['name']);
  final ref = _text(wayTags['ref']);
  if (name != null && ref != null) return '$name ($ref)';
  return name ?? ref;
}

/// Die OSM-Quelle eines Punkts. [type] ist `node` oder `relation`.
PointSource osmSource(String type, Object id, DateTime? updatedAt) =>
    osmSourceAt('https://www.openstreetmap.org/$type/$id', updatedAt);

/// Wie [osmSource], mit fertigem Link (so liegt sie im Kachel-Cache).
PointSource osmSourceAt(String? url, DateTime? updatedAt) => PointSource(
  id: 'osm',
  name: 'OpenStreetMap',
  attribution: osmAttribution,
  updatedAt: updatedAt,
  url: url,
);
