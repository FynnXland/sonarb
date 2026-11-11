import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/enforcement_tile.dart';
import 'legal.dart';
import 'privacy_screen.dart';
import 'services.dart';
import 'sonar_mark.dart';
import 'theme.dart';

const _seenKey = 'app.welcomeSeen';

/// Ob der Startbildschirm schon bestätigt wurde. Erst danach fragt das Cockpit nach dem Standort.
class WelcomeSeen extends Notifier<bool> {
  @override
  bool build() => ref.read(servicesProvider).prefs.getBool(_seenKey) ?? false;

  Future<void> confirm() async {
    state = true;
    await ref.read(servicesProvider).prefs.setBool(_seenKey, true);
  }
}

final welcomeSeenProvider = NotifierProvider<WelcomeSeen, bool>(
  WelcomeSeen.new,
);

/// Einmal vor der ersten Standortabfrage: wozu der Standort dient, was im Hintergrund läuft,
/// was die StVO sagt. Der Knopf führt direkt zur Abfrage des Systems.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                SonarSpace.xl,
                SonarSpace.xl,
                SonarSpace.xl,
                SonarSpace.l,
              ),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SonarMark(size: 72),
                ),
                const SizedBox(height: SonarSpace.l),
                Semantics(
                  header: true,
                  child: const Text(
                    'Vor der ersten Fahrt',
                    style: SonarText.warningKind,
                  ),
                ),
                const SizedBox(height: SonarSpace.xl),
                const _Point(
                  icon: Icons.my_location,
                  title: 'Standort',
                  text:
                      'Sonarb warnt vor festen Blitzern, Ampelblitzern und eigenen '
                      'Meldungen auf der Strecke. Dafür braucht die App den genauen '
                      'Standort. Den Fahrtverlauf speichert sie nicht.',
                ),
                const _Point(
                  icon: Icons.notifications_none,
                  title: 'Bei ausgeschaltetem Bildschirm',
                  text:
                      'Die Warnungen laufen weiter, wenn die App im Hintergrund ist. '
                      'Eine Benachrichtigung zeigt das an; „Beenden“ darin stoppt die '
                      'Überwachung.',
                ),
                const _Point(
                  icon: Icons.map_outlined,
                  title: 'Kartendaten',
                  text:
                      'Die Daten kommen aus OpenStreetMap. Beim Laden erfahren die '
                      'OpenStreetMap- und Overpass-Server den Kartenausschnitt um den '
                      'Standort.',
                ),
                const _Point(
                  icon: Icons.gavel_outlined,
                  title: 'Straßenverkehrsordnung',
                  text: stvoNotice,
                ),
                // Angebot, kein Zwang: Standard bleibt an, wie bisher.
                const EnforcementTile(
                  notice: false,
                  subtitle: welcomeEnforcementLine,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: SonarSpace.s),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                    ),
                    child: const Text('Datenschutzhinweise lesen'),
                  ),
                ),
              ],
            ),
          ),
          // Abstand nach oben: sonst klebt der letzte Listeneintrag am Knopf.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SonarSpace.xl,
              SonarSpace.m,
              SonarSpace.xl,
              SonarSpace.l,
            ),
            child: SizedBox(
              height: SonarSpace.driveTarget,
              child: FilledButton(
                onPressed: () =>
                    ref.read(welcomeSeenProvider.notifier).confirm(),
                child: const Text('Weiter zur Standortfreigabe'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SonarSpace.l),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: SonarColors.amber, size: 22),
        ),
        const SizedBox(width: SonarSpace.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SonarText.label),
              const SizedBox(height: SonarSpace.xs),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: SonarColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Unterzeile des Schalters „Blitzer-Funktionen“ auf dem Startbildschirm.
const welcomeEnforcementLine =
    'Lässt sich jederzeit in den Einstellungen ändern.';
