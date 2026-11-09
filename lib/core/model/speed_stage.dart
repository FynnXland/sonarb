/// Wie weit das Tempo über dem Limit liegt, in den Stufen, die das Cockpit farbig zeigt.
enum SpeedStage {
  /// Bis zum Limit, oder kein Limit bekannt.
  normal,

  /// Über dem Limit, aber noch in der eingestellten Toleranz: es piept noch nicht.
  tolerance,

  /// Über der Toleranz, bis 10 km/h über dem Limit.
  over,

  /// 11 bis 20 km/h über dem Limit, ab hier steigt das Bußgeld.
  high,

  /// Ab 21 km/h über dem Limit: das gibt einen Punkt in Flensburg.
  points,
}

/// Ab so viel km/h über dem Limit gibt es einen Punkt. Gerechnet ohne Toleranzabzug.
const int pointsOverKmh = 21;

/// Ab so viel km/h über dem Limit gilt [SpeedStage.high].
const int highOverKmh = 11;

/// Stufe für das angezeigte Tempo [speedKmh] beim Limit [limitKmh].
///
/// Die Grenze zwischen Toleranz und zu schnell kommt als [overspeed] von der Warnlogik, damit
/// Farbe und Piep gleich schalten. Die Stufen darüber zählen nur das angezeigte Tempo.
SpeedStage speedStageOf({
  required int speedKmh,
  required int? limitKmh,
  required bool overspeed,
}) {
  if (limitKmh == null) return SpeedStage.normal;
  final over = speedKmh - limitKmh;
  if (over >= pointsOverKmh) return SpeedStage.points;
  if (!overspeed) return over > 0 ? SpeedStage.tolerance : SpeedStage.normal;
  if (over >= highOverKmh) return SpeedStage.high;
  return SpeedStage.over;
}
