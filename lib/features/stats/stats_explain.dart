import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Wie eine Kennzahl berechnet ist, in einfachen Worten. Öffnet sich über das ⓘ.
class Explain {
  const Explain(this.title, this.text);

  final String title;
  final String text;
}

/// Alle Erklärungen der Fahrstatistik. Formeln und Schwellen: `docs/STATISTIK.md`.
abstract final class Explains {
  static const distance = Explain(
    'Strecke',
    'Das GPS-Tempo mal der Zeit, Sekunde für Sekunde aufaddiert. Fehlt GPS (Tunnel), zählt '
        'die Luftlinie zwischen den Messungen. Genau auf etwa 2 %.',
  );

  static const moving = Explain(
    'Fahrzeit',
    'Zeit, in der das Auto schneller als 3,6 km/h fuhr.',
  );

  static const stand = Explain(
    'Standzeit',
    'Zeit unter 3,6 km/h während der Fahrt, etwa an Ampeln oder im Stau. Das Stehen nach '
        'dem Parken zählt nicht mit.',
  );

  static const stops = Explain(
    'Halte',
    'Jedes Stehen ab 5 Sekunden ist ein Halt. Kriechen im Stau ist keiner.',
  );

  static const stopLength = Explain(
    'Dauer der Halte',
    'Längster Halt: das längste Stehen ab 5 Sekunden. Mittel: alle Halte zusammen geteilt '
        'durch ihre Anzahl.',
  );

  static const average = Explain(
    'Schnitt in Fahrt',
    'Strecke geteilt durch die Fahrzeit. Standzeiten zählen nicht mit.',
  );

  static const tripAverage = Explain(
    'Schnitt mit Stand',
    'Strecke geteilt durch Fahrzeit plus Standzeit. So schnell bist du insgesamt '
        'vorangekommen, Ampeln und Stau eingerechnet.',
  );

  static const maxSpeed = Explain(
    'Höchsttempo',
    'Das höchste Tempo, das mindestens drei Messungen in Folge (gut 2 Sekunden) gehalten '
        'wurde. Einzelne Ausreißer zählen so nicht. GPS misst das echte Tempo, der Tacho '
        'zeigt meist 3 bis 5 km/h mehr.',
  );

  static const frequent = Explain(
    'Am häufigsten',
    'Die 10-km/h-Stufe, in der du am längsten gefahren bist. Die Balken darunter zeigen den '
        'Anteil der Fahrzeit je Stufe.',
  );

  /// Gemeinsamer Hinweis für alles, was aus der Tempoänderung kommt.
  static const _gps =
      'Die Werte stammen aus dem GPS-Tempo, über drei Messungen geglättet, und sind deshalb '
      'Schätzungen, keine Messung aus dem Auto.';

  static const chart = Explain(
    'Tempoverlauf',
    'Das GPS-Tempo jede Sekunde über die Fahrzeit. Gestrichelt: das Tempolimit aus '
        'OpenStreetMap. Die Linie ist türkis im Limit (bis +3 km/h), gelb ab +4, rot ab +11 '
        'und dunkelrot ab +21 km/h; weiß, wo kein Limit bekannt ist. Unten die Bremsungen '
        '(gelb, rot ab 11 km/h pro Sekunde) und kräftiges Beschleunigen (türkis). Lücken ohne '
        'GPS sind gepunktet. Zum Ablesen den Finger über das Diagramm ziehen.',
  );

  static const calm = Explain(
    'Ruhig gefahren',
    'Anteil der Fahrzeit, in der sich das Tempo um weniger als 1,8 km/h pro Sekunde '
        '(0,5 m/s²) änderte. Gemessen jeweils über 2 Sekunden. Je höher, desto ruhiger. '
        '$_gps',
  );

  static const swing = Explain(
    'Schwankung',
    'Nur Abschnitte ab 20 Sekunden, in denen du ab 30 km/h weder gebremst noch beschleunigt '
        'hast. Für jeden Abschnitt: wie weit das Tempo im Mittel um seinen Durchschnitt '
        'pendelt (Standardabweichung). Die Abschnitte zählen nach ihrer Dauer. Unter 2 km/h '
        'ist sehr gleichmäßig. $_gps',
  );

  static const brakes = Explain(
    'Bremsungen',
    'Eine Verzögerung beginnt, wenn das Tempo um mindestens 1,8 km/h pro Sekunde fällt, und '
        'endet, wenn es kaum noch fällt. Sie zählt ab 7 km/h Tempoverlust. Bremsung: Spitze '
        'über 5 km/h pro Sekunde (1,5 m/s²). Hart: ab 11 km/h pro Sekunde (3 m/s²). Fällt das '
        'Tempo und ist sofort wieder da, schneller als ein Auto beschleunigen kann, ist das ein '
        'Messfehler und zählt nicht. $_gps',
  );

  static const maxDecel = Explain(
    'Stärkste Bremsung',
    'Die höchste Verzögerung, jeweils über 2 Sekunden gemessen, in km/h weniger pro Sekunde; '
        'klein daneben in m/s² (1 m/s² = 3,6 km/h pro Sekunde). Eine Vollbremsung (30 bis '
        '36 km/h pro Sekunde) erscheint durch Glättung und Messung über 2 Sekunden als etwa 20 '
        'bis 28 km/h pro Sekunde. $_gps',
  );

  static const decelSpread = Explain(
    'Verteilung der Verzögerungen',
    'Alle Verzögerungen ab 7 km/h Tempoverlust, nach ihrer Spitze in Stufen zu 1,8 km/h pro '
        'Sekunde (0,5 m/s²). Sanft: unter 5 km/h pro Sekunde (Ausrollen, Motorbremse, leichtes '
        'Bremsen). Mittel: 5 bis 11. Hart: ab 11 km/h pro Sekunde. $_gps',
  );

  static const gentle = Explain(
    'Sanft verzögert',
    'Anteil des gesamten Tempoabbaus aus Verzögerungen mit höchstens 1,5 m/s², die mindestens '
        '3 Sekunden dauerten. Geschätzt: Motorbremse, Ausrollen und leichtes Bremsen lassen '
        'sich ohne Daten aus dem Auto nicht trennen. $_gps',
  );

  static const starts = Explain(
    'Anfahrten',
    'Eine Beschleunigung, die unter 7 km/h beginnt und mindestens 7 km/h Tempo gewinnt. '
        'Kräftig: Spitze ab 11 km/h mehr pro Sekunde (3 m/s²). $_gps',
  );

  static const maxAccel = Explain(
    'Stärkste Beschleunigung',
    'Die höchste Beschleunigung, jeweils über 2 Sekunden gemessen, in km/h mehr pro Sekunde; '
        'klein daneben in m/s². Ein normales Anfahren liegt bei 4 bis 7 km/h pro Sekunde. '
        '$_gps',
  );

  static const accelSpread = Explain(
    'Verteilung der Beschleunigungen',
    'Alle Beschleunigungen ab 7 km/h Tempogewinn, nach ihrer Spitze in Stufen zu 1,8 km/h '
        'pro Sekunde (0,5 m/s²). Sanft: unter 5 km/h pro Sekunde. Mittel: 5 bis 11. Kräftig: '
        'ab 11 km/h pro Sekunde. $_gps',
  );

  static const curves = Explain(
    'Zügige Kurven',
    'Querbeschleunigung = Tempo mal Drehrate. Die Drehrate kommt aus der Änderung der '
        'GPS-Fahrtrichtung über 2 Sekunden, erst ab 18 km/h. Zügig ab 3,5 m/s². Eine Näherung; '
        'enge Kreisel werden unterschätzt.',
  );

  static const score = Explain(
    'Vorausschauend',
    'Mittel aus vier Teilen, jeder zwischen 0 und 1: sanft verzögert (Gewicht 35), wenig '
        'harte Bremsungen (25; ab 5 je 100 km gibt es 0), wenig zügige Kurven (20; ab 10 je '
        '100 km 0) und selten mehr als 10 km/h zu schnell (20; ab 20 % der Fahrzeit 0). Fehlt '
        'ein Teil, zählen die übrigen. Erst ab 1 km Strecke.',
  );

  static const overLimit = Explain(
    'Tempolimit nach Straßenart',
    'Fahrzeit mit bekanntem Limit aus OpenStreetMap, aufgeteilt nach dem Abstand zum Limit. '
        'Bis +3 km/h zählt als im Limit (Messtoleranz). Die Straßenart ist aus dem Limit '
        'geschätzt: bis 50 innerorts, bis 100 außerorts, darüber oder ohne Limit Autobahn.',
  );

  static const perLimit = Explain(
    'Je Tempolimit',
    'Für jedes Limit: wie lange du dort gefahren bist, welcher Anteil davon mehr als 3 km/h '
        'zu schnell war und das höchste gehaltene Tempo (drei Messungen in Folge).',
  );

  static const urban = Explain(
    'Innerorts',
    'Anteil der Fahrzeit auf Straßen mit Limit bis 50 km/h, gemessen an der Fahrzeit mit '
        'bekannter Straßenart. Geschätzt aus dem Limit.',
  );

  static const night = Explain(
    'Bei Dunkelheit',
    'Anteil der Fahrzeit, in der die Sonne mehr als 6° unter dem Horizont stand. Aus Ort und '
        'Uhrzeit gerechnet, nichts wird gespeichert.',
  );

  static const warnings = Explain(
    'Warnungen',
    'Die erste Ansage je Stelle, egal welcher Art.',
  );

  static const cameras = Explain(
    'Blitzer passiert',
    'Feste Blitzer und gemeldete mobile Blitzer, denen du auf 100 m nahegekommen bist. Zu '
        'schnell: Tempo bei der letzten Messung vor der Stelle über deren Limit plus 3 km/h.',
  );
}

/// Blatt mit der Erklärung [e].
Future<void> showExplain(BuildContext context, Explain e) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: SonarColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SonarSpace.l,
            0,
            SonarSpace.l,
            SonarSpace.l,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  e.title,
                  style: SonarText.label.copyWith(fontSize: 18),
                ),
              ),
              const SizedBox(height: SonarSpace.m),
              Text(
                e.text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: SonarColors.text,
                ),
              ),
              const SizedBox(height: SonarSpace.s),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Schließen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

/// Kleines ⓘ neben einer Kennzahl.
class ExplainMark extends StatelessWidget {
  const ExplainMark({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Icon(Icons.info_outline, size: 16, color: SonarColors.textMuted),
  );
}
