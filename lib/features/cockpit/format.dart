import '../../core/model/alert_point.dart';

/// „350 m“ (auf 10 m gerundet), ab 1 km „1,2 km“.
String formatDistance(double meters) {
  final rounded = (meters / 10).round() * 10;
  if (rounded < 1000) return '$rounded m';
  final km = (meters / 100).round() / 10;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

String alertKindLabel(AlertKind kind, {HotspotKind? reportKind}) =>
    switch (kind) {
      AlertKind.speedCamera => 'Blitzer',
      AlertKind.redLightCamera => 'Rotlichtblitzer',
      AlertKind.sectionControl => 'Abschnittskontrolle',
      AlertKind.trafficSignal => 'Ampel',
      AlertKind.hotspot => hotspotKindLabel(reportKind),
      AlertKind.live => 'Live',
      AlertKind.construction => 'Baustelle',
    };

String hotspotKindLabel(HotspotKind? kind) => switch (kind) {
  HotspotKind.mobileCamera => 'Mobiler Blitzer',
  HotspotKind.distanceCheck => 'Abstandsmessung',
  HotspotKind.construction => 'Baustelle',
  HotspotKind.danger => 'Gefahrenstelle',
  HotspotKind.other || null => 'Meldung',
};

/// Bezeichnung eines Punkts nach seiner feinen Art („Stauende“, „Fester Blitzer“).
String pointLabel(AlertPoint point) => point.effectiveCategory.label;
