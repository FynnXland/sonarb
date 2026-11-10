import 'package:flutter/foundation.dart';

/// Wer für die App verantwortlich ist, für die Datenschutzhinweise. Die Anschrift steht im
/// Impressum auf der Website, nicht im Code.
/// `tool/build-play.ps1` baut nicht, solange hier die Markierung für fehlende Angaben steht.
const appOperator =
    'Fynn Hansen, E-Mail: kontakt@fynnland.xyz. Anschrift: siehe fynn.land/impressum';

/// Rechtshinweis zu Blitzerwarnern, gleichlautend im Startbildschirm und unter „Über“.
const stvoNotice =
    'In Deutschland darf, wer ein Fahrzeug führt, keine Blitzerwarnung nutzen, '
    'auch nicht per App (§ 23 Abs. 1c StVO).';

/// Ein Abschnitt der Datenschutzhinweise.
typedef PrivacySection = ({String title, String body});

/// Datenschutzhinweise in der App. Die Datenschutzerklärung auf der Website (fynn.land) sagt
/// inhaltlich dasselbe; beide gleich halten.
const privacySections = <PrivacySection>[
  (
    title: 'Kurz',
    body:
        'Sonarb hat kein Konto, keine Werbung und keine Nutzungsstatistik. Einen '
        'Sonarb-Server gibt es nicht. Was die App speichert, bleibt auf dem Gerät.',
  ),
  (
    title: 'Standort',
    body:
        'Solange die Überwachung läuft, liest die App den genauen Standort, um vor '
        'Messstellen auf der Strecke zu warnen. Ist die App im Hintergrund oder der '
        'Bildschirm aus, läuft das weiter; eine Benachrichtigung zeigt es an, „Beenden“ '
        'stoppt es. Den Fahrtverlauf speichert die App nicht. Nach außen geht nur der '
        'Kartenausschnitt, siehe „Kartendaten“.',
  ),
  (
    title: 'Kartendaten',
    body:
        'Blitzer, Ampeln und Tempolimits lädt die App von öffentlichen Overpass-Servern '
        '(overpass-api.de, betrieben von FOSSGIS e. V., ersatzweise overpass.private.coffee). '
        'Die Kartenbilder kommen von tile.openstreetmap.org (OpenStreetMap Foundation). '
        'Diese Server erhalten dabei die IP-Adresse des Geräts und den Kartenausschnitt '
        'rund um den Standort. Für deren Verarbeitung gelten ihre eigenen Datenschutzhinweise. '
        'Geladene Daten bleiben als Zwischenspeicher auf dem Gerät und lassen sich in den '
        'Einstellungen unter „OSM-Cache“ löschen. Die Kartenbilder liegen im Cache-Ordner '
        'der App (bis etwa 1 GB); Android kann ihn jederzeit leeren, „Cache leeren“ in den '
        'Android-Einstellungen der App löscht ihn sofort.',
  ),
  (
    title: 'Tempolimit-Pakete',
    body:
        'Nur wenn Tempolimit-Pakete geladen werden: Das Verzeichnis und die Pakete kommen von '
        'GitHub (GitHub Inc., USA). GitHub erhält dabei die IP-Adresse des Geräts und erfährt, '
        'welches Bundesland gewählt wurde. Für die Verarbeitung dort gilt die '
        'Datenschutzerklärung von GitHub.',
  ),
  (
    title: 'Eigene Meldungen',
    body:
        'Gemeldete Stellen (Ort, Zeit, Art, Notiz) speichert die App nur auf dem Gerät. '
        'Weitergegeben werden sie nur über „Exportieren“, an das Ziel, das dabei gewählt wird.',
  ),
  (
    title: 'Fahrstatistik',
    body:
        'Nach jeder Fahrt speichert die App eine Zusammenfassung auf dem Gerät: Beginn und Ende, '
        'Strecke, Fahr- und Standzeit, Tempoverteilung, Zeit über dem Tempolimit, Bremsungen, '
        'Anfahrten, Kurven und passierte Blitzer. Orte und der Fahrtverlauf werden nicht '
        'gespeichert, die Daten verlassen das Gerät nicht. Fahrten bleiben höchstens ein Jahr. '
        'Unter „Fahrstatistik“ in den Einstellungen lässt sich die Aufzeichnung abschalten und '
        'jede Fahrt löschen.',
  ),
  (
    title: 'Navigationshinweise von Google Maps',
    body:
        'Nur wenn „Navigation von Google Maps nutzen“ eingeschaltet und Sonarb der Zugriff auf '
        'Mitteilungen erlaubt ist: Während einer Navigation liest Sonarb den Text der '
        'Navigationsmitteilung von Google Maps, etwa „In 300 m rechts auf B72“. Der Text bleibt '
        'nur im Arbeitsspeicher des Telefons, wird nicht gespeichert und nicht übertragen. '
        'Mitteilungen anderer Apps liest Sonarb nicht. Ausschalten lässt es sich in den '
        'Einstellungen unter „Warnung“; den Zugriff kann man jederzeit in den '
        'Android-Einstellungen entziehen.',
  ),
  (
    title: 'Berechtigungen',
    body:
        'Standort: für die Warnungen. Benachrichtigungen: Anzeige, solange die Überwachung '
        'läuft. Vordergrunddienst: hält die Überwachung bei ausgeschaltetem Bildschirm am '
        'Laufen. Internet: Laden der Kartendaten. Zugriff auf Mitteilungen (nur mit '
        'Freigabe): Navigationshinweise von Google Maps.',
  ),
  (
    title: 'Löschen',
    body:
        'Alle Daten der App verschwinden mit der Deinstallation oder über „Speicher löschen“ '
        'in den Android-Einstellungen der App.',
  ),
  (
    title: 'Rechte',
    body:
        'Es gibt die Rechte auf Auskunft, Berichtigung, Löschung, Einschränkung der '
        'Verarbeitung, Datenübertragung und Widerspruch (Art. 15 bis 21 DSGVO). Da die App '
        'keine Daten an den Verantwortlichen schickt, liegen dort in der Regel keine vor. '
        'Anfragen per E-Mail an die Adresse unten. Beschwerden nimmt der Landesbeauftragte '
        'für den Datenschutz Niedersachsen entgegen, Prinzenstraße 5, 30159 Hannover '
        '(Art. 77 DSGVO).',
  ),
  (title: 'Verantwortlich', body: appOperator),
];

/// Lizenz der Kartendaten auf der Lizenzseite, neben den Lizenzen der Pakete.
void registerDataLicenses() {
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(
        ['OpenStreetMap'],
        'Kartendaten © OpenStreetMap-Mitwirkende, verfügbar unter der Open Database '
        'License (ODbL) 1.0. Mehr unter openstreetmap.org/copyright.\n\n'
        'Kartenbilder: tile.openstreetmap.org, © OpenStreetMap-Mitwirkende.',
      ),
    ),
  );
}
