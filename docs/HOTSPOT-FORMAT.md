# Hotspot-Format

JSON-Datei für Export, Import und lokale Speicherung (`hotspots.json` hat dasselbe Format). UTF-8, Version 1.

```json
{
  "format": "sonarb-hotspots",
  "version": 1,
  "exportedAt": "2026-05-01T12:00:00.000Z",
  "hotspots": [
    {
      "id": "3f2b8c1e-5a47-4d0e-9b6a-1c2d3e4f5a6b",
      "lat": 52.5,
      "lon": 13.4,
      "kind": "mobileCamera",
      "headingDeg": 90.0,
      "note": null,
      "radiusMeters": 300,
      "createdAt": "2026-05-01T11:58:21.000Z"
    }
  ]
}
```

## Felder

| Feld | Typ | Bedeutung |
|---|---|---|
| `format` | String | Muss `sonarb-hotspots` sein. |
| `version` | Ganzzahl | Aktuell `1`. Höhere Versionen lehnt die App ab. |
| `exportedAt` | ISO-8601 | Zeitpunkt des Exports, wird beim Import ignoriert. |
| `hotspots` | Array | Einträge, neueste zuerst. |

Eintrag:

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `lat`, `lon` | ja | WGS84, `lat` -90..90, `lon` -180..180. |
| `id` | nein | Eindeutige Kennung (UUID v4). Fehlt sie, wird beim Import eine vergeben. |
| `kind` | nein | `mobileCamera` (Standard), `danger` oder `other`. Andere Werte machen den Eintrag ungültig. |
| `headingDeg` | nein | Fahrtrichtung in Grad (0 = Nord, im Uhrzeigersinn); `null` = alle Richtungen. |
| `note` | nein | Freitext oder `null`. |
| `radiusMeters` | nein | Abstand für das Hotspot-Signal, größer 0, Standard 300. |
| `createdAt` | nein | ISO-8601, Standard: Importzeitpunkt. |

## Import

- Kein JSON, falsches `format`, fehlende oder höhere `version`, fehlendes `hotspots`-Array: Import wird mit kurzer Meldung abgebrochen, nichts wird geändert.
- Ungültige Einträge (Koordinaten fehlen oder liegen außerhalb, unbekannte `kind`, falsche Feldtypen) werden gezählt (`invalid`), die übrigen übernommen.
- Duplikate werden übersprungen (`skippedDuplicates`): gleiche `id` oder gleiche `kind` näher als 25 m an einem vorhandenen Hotspot.
- Minimalformat: ein reines Array genügt, etwa `[{"lat": 52.5, "lon": 13.4}]`. Fehlende Felder erhalten die Standardwerte.

## Lokale Datei

`hotspots.json` wird atomar geschrieben (Temp-Datei, dann Umbenennen). Ist sie beim Start nicht lesbar, wird sie unverändert als `hotspots.json.defekt-<Zeitstempel>` beiseitegelegt und die App startet mit leerer Liste. Enthält sie einzelne ungültige Einträge, bleibt eine Kopie unter demselben Namensschema erhalten.
