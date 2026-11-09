import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/slow_loop.dart';
import '../../app/sonar_mark.dart';
import '../../app/theme.dart';
import '../../core/contracts/alert_repository.dart';

enum MapNoticeKind {
  /// Es wird geladen: Peilkeil dreht sich.
  loading,

  /// Laden gescheitert, für die Gegend fehlen Blitzer.
  failed,

  /// Es gibt Daten, aber nicht aktuell oder unvollständig.
  stale,

  /// Hinweis ohne Störung (Ausschnitt zu groß).
  info,
}

/// Was die Karte über den Ladestand sagt. [detail] ist eine zweite, kleinere Zeile.
class MapNotice {
  const MapNotice(this.kind, this.title, {this.detail});

  final MapNoticeKind kind;
  final String title;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is MapNotice &&
      other.kind == kind &&
      other.title == title &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, title, detail);
}

/// Hinweis zum Ladestand der Karte; null, wenn alles geladen ist und nichts zu sagen bleibt.
///
/// [coverage] gilt für die eigene Umgebung ([following]) oder den Ausschnitt; null heißt ohne
/// Standort. [tilesFailing]: Kartenkacheln kommen gerade nicht an.
MapNotice? mapNoticeFor({
  required DataCoverage? coverage,
  required bool following,
  required bool tilesFailing,
}) {
  if (coverage == null) {
    return following
        ? const MapNotice(MapNoticeKind.loading, 'Sucht Standort')
        : null;
  }
  const retry = 'Neuer Versuch folgt von selbst.';
  switch (coverage.state) {
    case CoverageState.loading:
      return MapNotice(
        MapNoticeKind.loading,
        following
            ? 'Lädt Blitzer in der Umgebung'
            : 'Lädt Blitzer im Ausschnitt',
      );
    case CoverageState.failed:
      return MapNotice(
        MapNoticeKind.failed,
        'Blitzer nicht geladen',
        detail: tilesFailing
            ? 'Keine Verbindung. $retry'
            : 'Server nicht erreichbar. $retry',
      );
    case CoverageState.stale:
      return MapNotice(
        MapNoticeKind.stale,
        'Gespeicherte Blitzer',
        detail: tilesFailing
            ? 'Keine Verbindung, Stand nicht aktuell'
            : 'Aktualisieren gescheitert, Stand nicht aktuell',
      );
    case CoverageState.tooWide:
      return const MapNotice(MapNoticeKind.info, 'Zum Laden näher heranzoomen');
    case CoverageState.ready:
      if (tilesFailing) {
        return const MapNotice(
          MapNoticeKind.stale,
          'Kartenbild offline',
          detail: 'Blitzer sind geladen',
        );
      }
      if (following && coverage.loadingPlugins.isNotEmpty) {
        return const MapNotice(MapNoticeKind.loading, 'Lädt weitere Quellen');
      }
      return null;
  }
}

/// Schild auf der Karte beim Mitführen. Den Ladestand der Umgebung zeigt schon das Hinweisfeld
/// über der Karte; hier steht nur, was dort fehlt: das Kartenbild kommt nicht an, oder
/// Zusatzquellen laden noch.
MapNotice? followingMapNotice({
  required DataCoverage? coverage,
  required bool tilesFailing,
}) {
  final ready = coverage?.state == CoverageState.ready;
  if (tilesFailing) {
    return MapNotice(
      MapNoticeKind.stale,
      'Kartenbild offline',
      detail: ready ? 'Blitzer sind geladen' : null,
    );
  }
  if (ready && coverage!.loadingPlugins.isNotEmpty) {
    return const MapNotice(MapNoticeKind.loading, 'Lädt weitere Quellen');
  }
  return null;
}

/// Schild oben links auf der Karte. Fest stehende Fläche, damit es über Kacheln und Dunst lesbar
/// bleibt; ein Live-Bereich, damit Screenreader den Wechsel ansagen.
class MapNoticeBadge extends StatelessWidget {
  const MapNoticeBadge({super.key, required this.notice, required this.still});

  final MapNotice notice;

  /// Keil steht still (Fahrt oder „Animationen aus“).
  final bool still;

  @override
  Widget build(BuildContext context) {
    final detail = notice.detail;
    final icon = switch (notice.kind) {
      MapNoticeKind.loading => SonarSweep(size: 22, still: still),
      MapNoticeKind.failed => const Icon(
        Icons.cloud_off,
        size: 22,
        color: SonarColors.text,
      ),
      MapNoticeKind.stale => const Icon(
        Icons.history,
        size: 22,
        color: SonarColors.textMuted,
      ),
      MapNoticeKind.info => const Icon(
        Icons.zoom_in,
        size: 22,
        color: SonarColors.textMuted,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: [notice.title, ?detail].join('. '),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SonarColors.surface,
          borderRadius: BorderRadius.circular(SonarRadius.s),
          border: Border.all(
            color: notice.kind == MapNoticeKind.failed
                ? SonarColors.text
                : SonarColors.outline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SonarSpace.m,
            vertical: SonarSpace.s,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: SonarSpace.s),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SonarText.small.copyWith(
                        color: SonarColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: SonarText.small,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Peilkeil des Logos, der kreist, solange geladen wird. Eine Umdrehung dauert so lange wie ein
/// Ring des Bereit-Zustands: langsam genug, um nicht zu zappeln. [still] hält ihn nach oben an.
class SonarSweep extends StatefulWidget {
  const SonarSweep({
    super.key,
    required this.size,
    required this.still,
    this.maxAlpha = 0.7,
    this.ring = true,
  });

  final double size;
  final bool still;
  final double maxAlpha;

  /// Äußerer Ring und Mittelpunkt wie im Logo; ohne bleibt nur der Keil (Kartenfläche).
  final bool ring;

  @override
  State<SonarSweep> createState() => SonarSweepState();
}

class SonarSweepState extends State<SonarSweep> {
  /// Höchstens 10 Bilder je Sekunde: der Keil kreist langsam, mehr sieht man nicht.
  final _c = SlowLoop(period: SonarMotion.standbyRing);

  /// Der Keil kreist gerade.
  @visibleForTesting
  bool get turning => _c.running;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SonarSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final still = widget.still || MediaQuery.disableAnimationsOf(context);
    if (still) {
      _c.stop();
    } else {
      _c.start();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SweepPainter(_c, widget.maxAlpha, widget.ring),
        ),
      ),
    ),
  );
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.t, this.maxAlpha, this.ring) : super(repaint: t);

  final ValueListenable<double> t;
  final double maxAlpha;
  final bool ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    paintBeam(canvas, c, r, t.value * 2 * math.pi, maxAlpha: maxAlpha);
    if (!ring) return;
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = SonarColors.amber,
    );
    canvas.drawCircle(c, r * 0.2, Paint()..color = SonarColors.amber);
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.t != t || old.maxAlpha != maxAlpha || old.ring != ring;
}
