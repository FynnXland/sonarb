# Plugins

Plugins sind optionale Zusatzquellen (z. B. ein privater Live-Feed). Die App funktioniert ohne sie vollständig.

Dart lädt keinen Code zur Laufzeit. Ein Plugin wird deshalb mitkompiliert, sein Code liegt aber in
`lib/plugins/local/`, das in `.gitignore` steht. Ein frischer Klon baut ohne Plugins. URLs und Zugangsdaten
bleiben so außerhalb des Repositorys.

## Plugin einsetzen

1. Ordner anlegen: `lib/plugins/local/<name>/` (Name nur aus `A–Z a–z 0–9 _ -`).
2. Vorlage kopieren: `lib/plugins/example/plugin.dart.template` nach `lib/plugins/local/<name>/plugin.dart`.
3. In der Kopie `id`, `displayName`, `baseUrl` und ggf. `bearerToken` eintragen. Die Funktion
   `DataSourcePlugin createPlugin()` muss auf oberster Ebene stehen, sonst findet der Generator sie nicht.
4. Einbinden: `dart run tool/plugins.dart`. Das Skript schreibt `lib/plugins/installed_plugins.dart` mit den
   Imports neu und setzt `git update-index --skip-worktree` auf diese Datei, damit sie nicht versehentlich
   committet wird. Es meldet beides.
5. Bauen und starten. In den Einstellungen das Plugin einschalten (Standard: aus).

Ein eigenes Plugin statt `JsonFeedPlugin` ist eine Klasse, die `DataSourcePlugin` implementiert und in
`plugin.dart` von `createPlugin()` zurückgegeben wird.

## Zurücksetzen

`dart run tool/plugins.dart --reset` stellt die leere Liste wieder her und hebt `skip-worktree` auf.
Danach baut das Projekt wieder ohne Plugins. Der Ordner `lib/plugins/local/` bleibt unberührt.

## Regeln (Interface `DataSourcePlugin`)

- `id` ist stabil und besteht aus `[a-z0-9_-]`. Unter ihr steht die Ein/Aus-Einstellung (`plugin.<id>.enabled`).
- Punkt-IDs beginnen mit `plugin:<id>:`, `AlertPoint.source` ist `<id>`. Andere IDs verwirft das Repository,
  Plugins können Core-Punkte nicht überschreiben.
- `fetch` wirft bei Fehlern. Das Repository fängt sie ab, zeigt Status `error` und behält die Punkte des letzten
  Erfolgs bis 15 Minuten nach diesem Erfolg.
- `fetch` bekommt 10 Sekunden. Danach gilt der Abruf als fehlgeschlagen (Zeitüberschreitung).
- `refreshInterval` ist der Mindestabstand zwischen zwei Abrufen. Bewegt sich der Fahrer mehr als 1,5 km vom
  letzten Abrufort weg, wird früher abgerufen.
- `initialize()` läuft beim Einschalten (oder beim ersten Abruf, wenn das Plugin schon eingeschaltet war),
  `dispose()` beim Ausschalten und beim Beenden.
- Liegt ein Plugin-Punkt gleicher Art weniger als 30 m von einem OSM-Punkt entfernt, entfällt der Plugin-Punkt.
- Zugangsdaten gehören in die lokale `plugin.dart`, nie in den Core oder ins Repository.

## JsonFeedPlugin

`lib/plugins/example/json_feed_plugin.dart` holt einen JSON-Feed per `GET`:

```
GET <baseUrl>?south=<lat>&west=<lon>&north=<lat>&east=<lon>
Authorization: Bearer <token>        (nur wenn ein Token gesetzt ist)
```

```json
{"points":[{"id":"a1","lat":52.5,"lon":13.4,"kind":"live","bearings":[90],"maxSpeed":50}]}
```

`kind` ist `live` (Standard) oder `speedCamera`. `bearings` (Fahrtrichtungen in Grad) und `maxSpeed` (km/h) sind
optional. Einträge ohne gültige `id`, `lat`, `lon` oder mit unbekanntem `kind` werden übersprungen.
