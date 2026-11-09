import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/model/speed_stage.dart';
import 'drive_state.dart';

/// Geschwindigkeit und Tempolimit nebeneinander. Höhe kommt vom Layout.
class SpeedRow extends StatelessWidget {
  const SpeedRow({super.key, required this.drive});

  final DriveState drive;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final signSize = (box.maxHeight * 0.86).clamp(56.0, 132.0);
      return Row(
        children: [
          Expanded(child: SpeedReadout(drive: drive)),
          const SizedBox(width: SonarSpace.m),
          SizedBox(
            width: signSize,
            child: Center(
              child: switch (drive.speedLimitKmh) {
                final kmh? => SpeedLimitSign(limitKmh: kmh, size: signSize),
                null when drive.noSpeedLimit => NoSpeedLimitSign(
                  size: signSize,
                ),
                null => const _NoLimit(),
              },
            ),
          ),
        ],
      );
    },
  );
}

class SpeedReadout extends StatelessWidget {
  const SpeedReadout({super.key, required this.drive});

  final DriveState drive;

  @override
  Widget build(BuildContext context) {
    final fix = drive.fix;
    if (fix == null || drive.stale) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          drive.stale ? 'GPS-Signal verloren' : 'Warte auf GPS',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: SonarText.warningKind.copyWith(color: SonarColors.textMuted),
        ),
      );
    }
    final kmh = fix.speedKmh.round();
    final stage = speedStageOf(
      speedKmh: kmh,
      limitKmh: drive.speedLimitKmh,
      overspeed: drive.overspeed,
    );
    final colors = speedStageColors(stage);
    final number = Text(
      '$kmh',
      style: SonarText.speed.copyWith(color: colors.text),
    );
    return Semantics(
      label: '$kmh Kilometer pro Stunde${_stageSpoken(stage)}',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (colors.fill case final fill?)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(SonarRadius.m * 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SonarSpace.m,
                    SonarSpace.s,
                    SonarSpace.m,
                    0,
                  ),
                  child: number,
                ),
              )
            else
              number,
            const SizedBox(width: SonarSpace.s),
            Text('km/h', style: SonarText.unit),
          ],
        ),
      ),
    );
  }
}

String _stageSpoken(SpeedStage stage) => switch (stage) {
  SpeedStage.normal => '',
  SpeedStage.tolerance => ', knapp über dem Limit',
  SpeedStage.over => ', zu schnell',
  SpeedStage.high => ', mehr als 10 zu schnell',
  SpeedStage.points => ', mehr als 20 zu schnell',
};

/// Rundes Verbotsschild wie an der Straße: weißer Grund, roter Rand, schwarze Zahl.
class SpeedLimitSign extends StatelessWidget {
  const SpeedLimitSign({super.key, required this.limitKmh, this.size = 96});

  final int limitKmh;
  final double size;

  @override
  Widget build(BuildContext context) {
    final digits = '$limitKmh'.length;
    return Semantics(
      label: 'Tempolimit $limitKmh',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: SonarColors.signWhite,
          shape: BoxShape.circle,
          border: Border.all(color: SonarColors.signRim, width: size * 0.11),
        ),
        alignment: Alignment.center,
        child: Text(
          '$limitKmh',
          style: SonarText.signNumber.copyWith(
            fontSize: size * (digits > 2 ? 0.34 : 0.44),
          ),
        ),
      ),
    );
  }
}

/// Zeichen 282 „Ende sämtlicher Streckenverbote“: weißer Grund, grauer Rand, schwarze
/// Schrägstriche. Steht, wo bekannt ist, dass kein Tempolimit gilt (Autobahn).
class NoSpeedLimitSign extends StatelessWidget {
  const NoSpeedLimitSign({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Kein Tempolimit',
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _NoLimitPainter()),
    ),
  );
}

class _NoLimitPainter extends CustomPainter {
  const _NoLimitPainter();

  /// Grauer Rand wie am echten Schild; hebt die weiße Scheibe auch von der dunklen Fläche ab.
  static const rim = Color(0xFF8A9299);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final rimWidth = r * 0.08;
    canvas.drawCircle(c, r, Paint()..color = rim);
    final inner = r - rimWidth;
    canvas.drawCircle(c, inner, Paint()..color = SonarColors.signWhite);
    // Fünf Striche von links unten nach rechts oben, in einem Band durch die Mitte.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: inner)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.785398); // −45°
    final stroke = Paint()
      ..color = SonarColors.signText
      ..strokeWidth = r * 0.055;
    for (var i = -2; i <= 2; i++) {
      final y = i * r * 0.14;
      canvas.drawLine(Offset(-r, y), Offset(r, y), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NoLimitPainter old) => false;
}

class _NoLimit extends StatelessWidget {
  const _NoLimit();

  @override
  Widget build(BuildContext context) => const FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      'Limit\nunbekannt',
      textAlign: TextAlign.center,
      style: SonarText.small,
    ),
  );
}

/// GPS-Güte als Symbol und Text.
class GpsIndicator extends StatelessWidget {
  const GpsIndicator({super.key, required this.drive});

  final DriveState drive;

  @override
  Widget build(BuildContext context) {
    final quality = drive.gpsQuality;
    final accuracy = drive.fix?.accuracyMeters.round();
    final (icon, text, color) = switch (quality) {
      GpsQuality.good => (Icons.gps_fixed, '±$accuracy m', SonarColors.text),
      GpsQuality.poor => (
        Icons.gps_not_fixed,
        '±$accuracy m',
        SonarColors.amber,
      ),
      GpsQuality.none => (
        Icons.gps_off,
        'Kein GPS',
        drive.running ? SonarColors.red : SonarColors.textMuted,
      ),
    };
    final label = quality == GpsQuality.none
        ? text
        : 'GPS-Genauigkeit $accuracy Meter';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: SonarSpace.xs),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SonarText.label.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
