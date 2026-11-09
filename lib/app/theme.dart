import 'package:flutter/material.dart';

import '../core/model/speed_stage.dart';

/// Farben. Kontrast der Kernwerte gegen [bg] (WCAG): text 17,2:1, amber 10,4:1,
/// red 7,5:1, hotspot 10,4:1, textMuted 8,7:1. Dunkle Schrift auf den Füllfarben ebenso.
abstract final class SonarColors {
  /// Gleich dem Grund des Android-Splash und des Launcher-Icons, damit der Start nahtlos ist.
  static const bg = Color(0xFF0E1114);
  static const surface = Color(0xFF1A1E23);
  static const surfaceHigh = Color(0xFF252A30);

  /// Ränder und Bedienelement-Kanten, 3,3:1 gegen [bg].
  static const outline = Color(0xFF5E6873);

  static const text = Color(0xFFF2F4F5);
  static const textMuted = Color(0xFFA9B1BA);

  /// Text auf den Füllfarben [amber], [red], [hotspot].
  static const onSignal = Color(0xFF0E1114);

  /// Vorwarnung.
  static const amber = Color(0xFFFFB020);

  /// Hauptwarnung und Überschreitung.
  static const red = Color(0xFFFF7A6E);

  /// Eigene Hotspots.
  static const hotspot = Color(0xFF3FD5C3);

  /// Live-Punkte aus Plugins.
  static const live = Color(0xFFD7DCE1);

  /// Verkehrszeichen: echtes Schild, deshalb eigene Farben.
  static const signWhite = Color(0xFFFFFFFF);
  static const signRim = Color(0xFFD2161E);
  static const signText = Color(0xFF000000);

  /// Tempo über dem Limit, von hell nach rot (siehe `SpeedStage`). Jede Stufe ist dunkler und
  /// röter als die davor. Gegen [bg]: 14,7:1, 10,4:1, 8,1:1; die letzte ist [red] als Fläche.
  static const speedTolerance = Color(0xFFFFE08A);
  static const speedOver = amber;
  static const speedHigh = Color(0xFFFF8A3D);
}

/// Farbe des Tempos je Stufe: Schrift und, nur bei [SpeedStage.points], die Fläche dahinter.
/// Ab einem Punkt in Flensburg steht die Zahl dunkel auf Rot, damit die Stufe sich vom Orange
/// davor klar abhebt.
({Color text, Color? fill}) speedStageColors(SpeedStage stage) =>
    switch (stage) {
      SpeedStage.normal => (text: SonarColors.text, fill: null),
      SpeedStage.tolerance => (text: SonarColors.speedTolerance, fill: null),
      SpeedStage.over => (text: SonarColors.speedOver, fill: null),
      SpeedStage.high => (text: SonarColors.speedHigh, fill: null),
      SpeedStage.points => (text: SonarColors.onSignal, fill: SonarColors.red),
    };

abstract final class SonarSpace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;

  /// Mindesthöhe für Bedienelemente während der Fahrt.
  static const driveTarget = 64.0;
}

/// Zeiten für Bewegung. Kurz und weich; wer Animationen abschaltet, bekommt keine.
abstract final class SonarMotion {
  static const fade = Duration(milliseconds: 260);

  /// Peilkeil des Logos beim Start.
  static const intro = Duration(milliseconds: 1300);

  /// Ein Ring des Bereit-Zustands wandert nach außen.
  static const standbyRing = Duration(milliseconds: 3600);

  /// Ring um die eigene Position.
  static const ownRing = Duration(milliseconds: 2800);

  /// Atmen der Warnfläche.
  static const warning = Duration(milliseconds: 1400);
}

abstract final class SonarRadius {
  static const s = 6.0;
  static const m = 10.0;
}

abstract final class SonarText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Geschwindigkeit. Größe setzt das Layout per FittedBox.
  static const speed = TextStyle(
    fontSize: 112,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -2,
    color: SonarColors.text,
    fontFeatures: _tabular,
  );

  static const unit = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: SonarColors.textMuted,
  );

  static const distance = TextStyle(
    fontSize: 34,
    height: 1.0,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
  );

  static const warningKind = TextStyle(
    fontSize: 22,
    height: 1.1,
    fontWeight: FontWeight.w700,
  );

  static const signNumber = TextStyle(
    fontWeight: FontWeight.w800,
    color: SonarColors.signText,
    height: 1.0,
    letterSpacing: -1,
    fontFeatures: _tabular,
  );

  static const label = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: SonarColors.text,
  );

  static const small = TextStyle(fontSize: 13, color: SonarColors.textMuted);

  static const button = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
}

/// Nur Dark-Mode: nachts im Auto blendet ein heller Bildschirm.
ThemeData buildSonarTheme() {
  const scheme = ColorScheme.dark(
    surface: SonarColors.bg,
    onSurface: SonarColors.text,
    onSurfaceVariant: SonarColors.textMuted,
    surfaceContainerLowest: SonarColors.bg,
    surfaceContainerLow: SonarColors.surface,
    surfaceContainer: SonarColors.surface,
    surfaceContainerHigh: SonarColors.surfaceHigh,
    surfaceContainerHighest: SonarColors.surfaceHigh,
    primary: SonarColors.amber,
    onPrimary: SonarColors.onSignal,
    secondary: SonarColors.hotspot,
    onSecondary: SonarColors.onSignal,
    error: SonarColors.red,
    onError: SonarColors.onSignal,
    outline: SonarColors.outline,
    outlineVariant: SonarColors.surfaceHigh,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(SonarRadius.m),
  );
  return ThemeData(
    useMaterial3: true,
    // Schlichte Welle statt Glitzer-Effekt: ruhiger beim Blick während der Fahrt.
    splashFactory: InkRipple.splashFactory,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: SonarColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: SonarColors.bg,
      foregroundColor: SonarColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        textStyle: SonarText.button,
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: SonarColors.text,
        side: const BorderSide(color: SonarColors.outline),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: SonarColors.amber,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: SonarColors.surfaceHigh,
      space: 1,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: SonarColors.surfaceHigh,
      contentTextStyle: TextStyle(color: SonarColors.text, fontSize: 15),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: SonarColors.textMuted,
      textColor: SonarColors.text,
    ),
  );
}
