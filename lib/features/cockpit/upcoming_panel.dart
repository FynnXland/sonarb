import 'package:flutter/material.dart';

import '../../app/slow_loop.dart';
import '../../app/theme.dart';
import '../../core/contracts/alert_repository.dart';
import '../../core/contracts/warning_engine.dart';
import '../../core/model/alert_point.dart';
import 'format.dart';
import 'instruments.dart';
import 'symbols/category_symbol.dart';
import 'map_data_notice.dart';

/// Wie viele Punkte nach dem nächsten noch klein darunter stehen.
const upcomingExtraRows = 2;

/// Alles, was voraus liegt: der nächste Punkt groß mit Art und Abstand, ein bis zwei weitere
/// klein darunter. Die Stufe zeigt Füllfarbe und Text, nicht nur Farbe.
class UpcomingPanel extends StatelessWidget {
  const UpcomingPanel({
    super.key,
    required this.upcoming,
    this.height = 72,
    this.coverage = DataCoverage.ready,
    this.still = false,
    this.onOpen,
    this.extraRows = upcomingExtraRows,
    this.enforcement = true,
  });

  final List<ActiveWarning> upcoming;

  /// Blitzer-Funktionen an; aus steht das in der leeren Zeile.
  final bool enforcement;

  /// Wie viele weitere Punkte klein darunter stehen; auf engen Bildschirmen weniger.
  final int extraRows;

  /// Tippen auf die große Zeile: Angaben zum nächsten Punkt. Nur die große Zeile, denn die
  /// kleinen darunter wären als Tippfläche zu niedrig.
  final ValueChanged<AlertPoint>? onOpen;

  /// Ladestand der Umgebung; null ohne Standort. Bestimmt, was bei leerer Liste dasteht:
  /// „Keine Messstelle voraus“ nur, wenn wirklich geladen ist.
  final DataCoverage? coverage;

  /// Ladekeil steht still (Fahrt).
  final bool still;

  /// Höhe der großen Zeile.
  final double height;

  @override
  Widget build(BuildContext context) {
    final first = upcoming.isEmpty ? null : upcoming.first;
    final more = upcoming.skip(1).take(extraRows).toList();
    return AnimatedSize(
      duration: SonarMotion.fade,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (first == null)
            _Empty(
              height: height,
              coverage: coverage,
              still: still,
              enforcement: enforcement,
            )
          else
            _Lead(
              first,
              height,
              onTap: onOpen == null ? null : () => onOpen!(first.point),
            ),
          for (final w in more) _Next(w),
        ],
      ),
    );
  }
}

/// Text der leeren Zeile je Ladestand: (Hauptzeile, Zusatz, lädt gerade). Ohne
/// Blitzer-Funktionen ([enforcement] aus) sagt der Zusatz das, damit „nichts voraus“ nicht nach
/// „kein Blitzer voraus“ klingt.
(String, String?, bool) emptyUpcomingText(
  DataCoverage? coverage, {
  bool enforcement = true,
}) => enforcement
    ? _emptyWithCameras(coverage)
    : switch (coverage?.state) {
        null => ('Wartet auf Standort', enforcementOffLine, true),
        CoverageState.loading => (
          'Lädt Daten der Umgebung',
          enforcementOffLine,
          true,
        ),
        CoverageState.failed => (
          'Keine Daten für diese Gegend',
          'Laden gescheitert, neuer Versuch folgt',
          false,
        ),
        CoverageState.stale => (
          enforcementOffEmpty,
          'Blitzer aus · Daten nicht aktuell',
          false,
        ),
        CoverageState.ready || CoverageState.tooWide => (
          enforcementOffEmpty,
          enforcementOffLine,
          false,
        ),
      };

/// Leeres Hinweisfeld ohne Blitzer-Funktionen. Nicht „Nichts voraus“: Das klänge nach „kein
/// Blitzer voraus“, obwohl Sonarb dann gar nicht nach Blitzern sieht.
const enforcementOffEmpty = 'Keine Baustelle oder Gefahr voraus';

/// Zusatz im Hinweisfeld ohne Blitzer-Funktionen.
const enforcementOffLine = 'Blitzer-Funktionen sind aus';

(String, String?, bool) _emptyWithCameras(DataCoverage? coverage) =>
    switch (coverage?.state) {
      null => ('Wartet auf Standort', null, true),
      CoverageState.loading => ('Lädt Blitzer in der Umgebung', null, true),
      CoverageState.failed => (
        'Keine Blitzerdaten für diese Gegend',
        'Laden gescheitert, neuer Versuch folgt',
        false,
      ),
      CoverageState.stale => (
        'Keine Messstelle voraus',
        'laut gespeicherten Daten, nicht aktuell',
        false,
      ),
      CoverageState.ready ||
      CoverageState.tooWide => ('Keine Messstelle voraus', null, false),
    };

class _Empty extends StatelessWidget {
  const _Empty({
    required this.height,
    required this.coverage,
    required this.still,
    required this.enforcement,
  });

  final double height;
  final DataCoverage? coverage;
  final bool still;
  final bool enforcement;

  @override
  Widget build(BuildContext context) {
    final (title, detail, loading) = emptyUpcomingText(
      coverage,
      enforcement: enforcement,
    );
    final failed = coverage?.state == CoverageState.failed;
    return Semantics(
      liveRegion: true,
      label: [title, ?detail].join(', '),
      excludeSemantics: true,
      child: Container(
        // Mindesthöhe: bei großer Schrift wächst die Zeile, statt abzuschneiden.
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
        decoration: BoxDecoration(
          color: SonarColors.surface,
          borderRadius: BorderRadius.circular(SonarRadius.m),
          border: failed ? Border.all(color: SonarColors.outline) : null,
        ),
        child: Row(
          children: [
            if (loading) ...[
              SonarSweep(size: 20, still: still),
              const SizedBox(width: SonarSpace.m),
            ] else if (failed) ...[
              const Icon(Icons.cloud_off, size: 20, color: SonarColors.text),
              const SizedBox(width: SonarSpace.m),
            ] else if (!enforcement) ...[
              const Icon(
                Icons.no_photography_outlined,
                size: 20,
                color: SonarColors.amber,
              ),
              const SizedBox(width: SonarSpace.m),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: detail == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: failed
                        ? SonarText.small.copyWith(
                            color: SonarColors.text,
                            fontWeight: FontWeight.w600,
                          )
                        : SonarText.small,
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SonarText.small,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Schild in der großen Zeile und in den kleinen darunter.
const pointSignLead = 40.0;
const pointSignNext = 24.0;

/// Kartensymbol daneben (Durchmesser des Nadelkopfs).
const pointSymbolLead = 26.0;
const pointSymbolNext = 16.0;

/// Wie schnell man am Punkt sein darf, für die Ansage im Screenreader.
String _limitSpeech(AlertPoint p) =>
    p.maxSpeed == null ? '' : ', Limit ${p.maxSpeed} km/h';

/// Tempo, bei dem der Punkt auslöst, als kleines Limit-Schild. Es kann vom Limit der Straße
/// oben abweichen (vor dem Blitzer noch 70, am Blitzer 50). Ohne bekanntes Limit nichts.
/// Auf farbiger Fläche mit dunklem Rand, damit sich das weiße Schild abhebt.
class PointLimitSign extends StatelessWidget {
  const PointLimitSign({
    super.key,
    required this.limitKmh,
    required this.size,
    this.outlined = false,
  });

  final int limitKmh;
  final double size;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final sign = SpeedLimitSign(limitKmh: limitKmh, size: size);
    if (!outlined) return sign;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: SonarColors.onSignal, width: 2),
      ),
      child: sign,
    );
  }
}

String _levelText(WarningLevel level) => switch (level) {
  WarningLevel.main => 'Hauptwarnung',
  WarningLevel.pre => 'Vorwarnung',
  WarningLevel.none => 'voraus',
};

class _Lead extends StatelessWidget {
  const _Lead(this.warning, this.height, {this.onTap});

  final ActiveWarning warning;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final level = warning.level;
    final fill = switch (level) {
      WarningLevel.main => SonarColors.red,
      WarningLevel.pre => SonarColors.amber,
      WarningLevel.none => SonarColors.surfaceHigh,
    };
    final ink = level == WarningLevel.none
        ? SonarColors.text
        : SonarColors.onSignal;
    final kind = warning.point.effectiveCategory.label;
    final distance = formatDistance(warning.distanceMeters);
    final levelText = _levelText(level);
    final limit = warning.point.maxSpeed;
    final radius = BorderRadius.circular(SonarRadius.m);
    return Semantics(
      liveRegion: true,
      button: onTap != null,
      hint: onTap == null ? null : 'Angaben anzeigen',
      label: '$levelText: $kind in $distance${_limitSpeech(warning.point)}',
      excludeSemantics: true,
      onTap: onTap,
      child: _Breathing(
        active: level != WarningLevel.none,
        child: Material(
          color: fill,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              // Mindesthöhe: bei großer Schrift wächst die Zeile, statt abzuschneiden.
              constraints: BoxConstraints(minHeight: height),
              padding: const EdgeInsets.symmetric(horizontal: SonarSpace.l),
              child: LayoutBuilder(
                builder: (context, box) => Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Zwei Zeilen: Bezeichnungen wie „Fester Blitzer für Rotlicht und
                          // Tempo“ sind lang.
                          Text(
                            kind,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SonarText.warningKind.copyWith(color: ink),
                          ),
                          Text(
                            levelText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SonarText.small.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Das Kartensymbol ohne Zahl neben dem Schild, damit die Zahl nicht
                    // doppelt steht.
                    const SizedBox(width: SonarSpace.s),
                    CategorySymbol(
                      warning.point.effectiveCategory,
                      size: pointSymbolLead,
                    ),
                    if (limit != null) ...[
                      const SizedBox(width: SonarSpace.s),
                      PointLimitSign(
                        limitKmh: limit,
                        size: pointSignLead,
                        outlined: level != WarningLevel.none,
                      ),
                      const SizedBox(width: SonarSpace.m),
                    ],
                    // Höchstens die Hälfte der Zeile: bei großer Schrift wird der Abstand
                    // kleiner, statt die Zeile zu sprengen.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          distance,
                          style: SonarText.distance.copyWith(color: ink),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Next extends StatelessWidget {
  const _Next(this.warning);

  final ActiveWarning warning;

  @override
  Widget build(BuildContext context) {
    final kind = warning.point.effectiveCategory.label;
    final distance = formatDistance(warning.distanceMeters);
    final limit = warning.point.maxSpeed;
    return Semantics(
      label: '$kind in $distance${_limitSpeech(warning.point)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: SonarSpace.xs,
          left: SonarSpace.l,
          right: SonarSpace.l,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  kind,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SonarText.label.copyWith(color: SonarColors.textMuted),
                ),
              ),
              const SizedBox(width: SonarSpace.s),
              CategorySymbol(
                warning.point.effectiveCategory,
                size: pointSymbolNext,
              ),
              if (limit != null) ...[
                const SizedBox(width: SonarSpace.s),
                PointLimitSign(limitKmh: limit, size: pointSignNext),
                const SizedBox(width: SonarSpace.s),
              ],
              Text(
                distance,
                style: SonarText.label.copyWith(color: SonarColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Heller Rand, der langsam an- und abschwillt, solange eine Warnung ansteht. Er lenkt
/// den Blick auf die Fläche, ohne zu blinken. Ohne Animationen steht er still.
class _Breathing extends StatefulWidget {
  const _Breathing({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> {
  /// Höchstens 10 Bilder je Sekunde; das langsame Schwellen braucht nicht mehr.
  final _c = SlowLoop(period: SonarMotion.warning * 2, reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Breathing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      _c.start();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (_, child) => DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SonarRadius.m),
        border: widget.active
            ? Border.all(
                color: SonarColors.text.withValues(
                  alpha: 0.15 + 0.5 * _c.value,
                ),
                width: 3,
              )
            : null,
      ),
      child: child,
    ),
  );
}
