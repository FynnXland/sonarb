import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/contracts/maps_navigation.dart';

/// Hinweis vor der Systemfreigabe (Play: deutlicher Hinweis vor dem Zugriff auf Daten).
const mapsNavDisclosure =
    'Sonarb liest während einer Navigation den Text der Navigationsmitteilung von Google '
    'Maps, etwa „In 300 m rechts auf B72“. Der Text bleibt nur im Arbeitsspeicher des '
    'Telefons, wird nicht gespeichert und nicht übertragen. Mitteilungen anderer Apps liest '
    'Sonarb nicht.\n\n'
    'Dafür braucht Sonarb in Android den Zugriff auf Mitteilungen. Ist der Schalter dort '
    'gesperrt, erst in den App-Infos von Sonarb über das Menü „Eingeschränkte '
    'Einstellungen zulassen“ wählen.';

/// Zeile unter dem Schalter: was zuletzt von Maps kam.
String mapsReadingLine(MapsReading? r) {
  if (r == null) return 'Noch keine Navigation von Google Maps gesehen';
  final h = r.at.hour.toString().padLeft(2, '0');
  final m = r.at.minute.toString().padLeft(2, '0');
  if (!r.readable) {
    return 'Mitteilung erkannt, aber ohne lesbaren Text ($h:$m)';
  }
  return 'Zuletzt von Maps gelesen ($h:$m): ${r.parts.join(' · ')}';
}

/// Schalter „Navigation von Google Maps nutzen“ unter „Warnung“. Einschalten zeigt erst den
/// Hinweis, dann die Freigabe in Android. Ohne Freigabe springt der Schalter zurück.
class MapsNavTile extends ConsumerStatefulWidget {
  const MapsNavTile({super.key});

  @override
  ConsumerState<MapsNavTile> createState() => _MapsNavTileState();
}

class _MapsNavTileState extends ConsumerState<MapsNavTile>
    with WidgetsBindingObserver {
  bool? _granted;
  bool _awaitingGrant = false;
  MapsReading? _reading;
  StreamSubscription<MapsReading>? _sub;

  MapsNavigation get _maps => ref.read(servicesProvider).mapsNavigation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = _maps.readings.listen((r) {
      if (mounted) setState(() => _reading = r);
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  /// Freigabe und letzten Stand neu holen. Kam man von der Systemseite ohne Freigabe zurück,
  /// geht der Schalter aus.
  Future<void> _refresh() async {
    final granted = await _maps.granted();
    final latest = await _maps.latest();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _reading = latest ?? _reading;
    });
    if (_awaitingGrant) {
      _awaitingGrant = false;
      if (!granted) {
        await ref
            .read(appSettingsProvider.notifier)
            .change((x) => x.copyWith(mapsNavigation: false));
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Zugriff nicht erteilt')));
      }
    }
  }

  Future<void> _turnOn() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Navigation von Google Maps nutzen'),
        content: const SingleChildScrollView(child: Text(mapsNavDisclosure)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nicht jetzt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erlauben'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref
        .read(appSettingsProvider.notifier)
        .change((x) => x.copyWith(mapsNavigation: true));
    if (await _maps.granted()) {
      if (mounted) setState(() => _granted = true);
      return;
    }
    _awaitingGrant = true;
    if (!await _maps.openAccessSettings()) _awaitingGrant = false;
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(appSettingsProvider.select((s) => s.mapsNavigation));
    final String subtitle;
    if (!on) {
      subtitle =
          'Liest die Navigationsmitteilung von Google Maps. Noch eine Probe: '
          'Die Warnungen nutzen sie noch nicht.';
    } else if (_granted == false) {
      subtitle = 'Zugriff in Android nicht erteilt';
    } else {
      subtitle = mapsReadingLine(_reading);
    }
    final tile = SwitchListTile(
      title: const Text('Navigation von Google Maps nutzen'),
      subtitle: Text(subtitle, style: SonarText.small),
      value: on,
      onChanged: (v) {
        if (v) {
          unawaited(_turnOn());
        } else {
          unawaited(
            ref
                .read(appSettingsProvider.notifier)
                .change((x) => x.copyWith(mapsNavigation: false)),
          );
        }
      },
    );
    if (!on || _granted != false) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.only(left: SonarSpace.s),
          child: TextButton(
            onPressed: () async {
              _awaitingGrant = await _maps.openAccessSettings();
            },
            child: const Text('Zugriff in Android erteilen'),
          ),
        ),
      ],
    );
  }
}
