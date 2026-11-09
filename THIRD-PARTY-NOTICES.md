# Fremdlizenzen

Sonarb selbst steht unter der [MIT-Lizenz](LICENSE). Die App enthält Pakete und nutzt Daten
anderer, deren Lizenzen hier stehen. In der App zeigt Einstellungen → Über → „Lizenzen“ die
vollständigen Lizenztexte der eingebauten Pakete.

Diese Datei erzeugt `dart run tool/third_party_notices.dart`; bitte nicht von Hand ändern.

## Kartendaten

- **OpenStreetMap:** Blitzer, Ampeln und Tempolimits kommen zur Laufzeit aus OpenStreetMap.
  Daten © OpenStreetMap-Mitwirkende, verfügbar unter der
  [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/),
  siehe [openstreetmap.org/copyright](https://www.openstreetmap.org/copyright).
- **Ausnahme von der MIT-Lizenz:** Diese Dateien im Repository stammen aus OpenStreetMap und
  stehen unter der ODbL, © OpenStreetMap-Mitwirkende: die Testdaten `test/osm/*.json` und
  `test/osm/parity/*` (darunter `golden.sblp`), die Teststrecke `tool/media/route.json` und das
  Länderraster `lib/features/osm/land_grid.dart`.
- **Dienste:** Die App fragt die öffentlichen Overpass-Server `overpass-api.de` (FOSSGIS e. V.)
  und `overpass.private.coffee` sowie den Kachelserver `tile.openstreetmap.org`
  (OpenStreetMap Foundation) ab. Für sie gelten deren Nutzungsregeln.

## Flutter

- **Flutter SDK** (BSD-3-Clause), https://github.com/flutter/flutter
- **Material Icons** (Apache-2.0), mit Flutter ausgeliefert

## Verwendete Pakete

Alle Pakete, die in der App stecken, einschließlich indirekter Abhängigkeiten.
Plattform-Implementierungen für Web, Windows, Linux und macOS landen nicht in der Android-App.

| Paket | Version | Lizenz |
|---|---|---|
| [android_file_picker](https://pub.dev/packages/android_file_picker) | 2.1.2 | MIT |
| [archive](https://pub.dev/packages/archive) | 4.5.2 | MIT |
| [args](https://pub.dev/packages/args) | 2.7.0 | BSD-3-Clause |
| [async](https://pub.dev/packages/async) | 2.13.1 | BSD-3-Clause |
| [audio_session](https://pub.dev/packages/audio_session) | 0.2.4 | MIT |
| [boolean_selector](https://pub.dev/packages/boolean_selector) | 2.1.2 | BSD-3-Clause |
| [characters](https://pub.dev/packages/characters) | 1.4.1 | BSD-3-Clause |
| [clock](https://pub.dev/packages/clock) | 1.1.3 | Apache-2.0 |
| [code_assets](https://pub.dev/packages/code_assets) | 1.2.1 | BSD-3-Clause |
| [collection](https://pub.dev/packages/collection) | 1.19.1 | BSD-3-Clause |
| [cross_file](https://pub.dev/packages/cross_file) | 0.3.5+5 | BSD-3-Clause |
| [crypto](https://pub.dev/packages/crypto) | 3.0.8 | BSD-3-Clause |
| [dart_earcut](https://pub.dev/packages/dart_earcut) | 1.2.0 | MIT |
| [dart_polylabel2](https://pub.dev/packages/dart_polylabel2) | 1.0.0 | BSD-3-Clause |
| [dbus](https://pub.dev/packages/dbus) | 0.8.0 | MPL-2.0 |
| [fake_async](https://pub.dev/packages/fake_async) | 1.3.3 | Apache-2.0 |
| [ffi](https://pub.dev/packages/ffi) | 2.2.0 | BSD-3-Clause |
| [ffi_leak_tracker](https://pub.dev/packages/ffi_leak_tracker) | 0.1.2 | BSD-3-Clause |
| [file](https://pub.dev/packages/file) | 7.0.1 | BSD-3-Clause |
| [file_picker](https://pub.dev/packages/file_picker) | 13.3.0 | MIT |
| [file_picker_darwin](https://pub.dev/packages/file_picker_darwin) | 2.4.0 | MIT |
| [file_picker_linux](https://pub.dev/packages/file_picker_linux) | 2.0.2 | MIT |
| [file_picker_platform_interface](https://pub.dev/packages/file_picker_platform_interface) | 4.2.0 | MIT |
| [file_picker_web](https://pub.dev/packages/file_picker_web) | 4.2.0 | MIT |
| [fixnum](https://pub.dev/packages/fixnum) | 1.1.1 | BSD-3-Clause |
| [flutter_foreground_task](https://pub.dev/packages/flutter_foreground_task) | 11.0.3 | MIT |
| [flutter_map](https://pub.dev/packages/flutter_map) | 8.3.2 | BSD-3-Clause |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | 3.4.3 | MIT |
| [flutter_tts](https://pub.dev/packages/flutter_tts) | 4.2.5 | MIT |
| [geolocator](https://pub.dev/packages/geolocator) | 14.0.1 | MIT |
| [geolocator_android](https://pub.dev/packages/geolocator_android) | 5.2.1 | MIT |
| [geolocator_apple](https://pub.dev/packages/geolocator_apple) | 2.4.3 | MIT |
| [geolocator_platform_interface](https://pub.dev/packages/geolocator_platform_interface) | 4.4.1 | MIT |
| [geolocator_web](https://pub.dev/packages/geolocator_web) | 4.1.4 | MIT |
| [geolocator_windows](https://pub.dev/packages/geolocator_windows) | 0.2.5 | MIT |
| [hooks](https://pub.dev/packages/hooks) | 2.0.2 | BSD-3-Clause |
| [http](https://pub.dev/packages/http) | 1.6.0 | BSD-3-Clause |
| [http_parser](https://pub.dev/packages/http_parser) | 4.1.2 | BSD-3-Clause |
| [intl](https://pub.dev/packages/intl) | 0.20.3 | BSD-3-Clause |
| [jni](https://pub.dev/packages/jni) | 1.1.1 | BSD-3-Clause |
| [jni_flutter](https://pub.dev/packages/jni_flutter) | 1.0.4+1 | BSD-3-Clause |
| [jni_util](https://pub.dev/packages/jni_util) | 1.0.0 | BSD-3-Clause |
| [just_audio](https://pub.dev/packages/just_audio) | 0.10.6 | Apache-2.0 |
| [just_audio_platform_interface](https://pub.dev/packages/just_audio_platform_interface) | 4.6.0 | MIT |
| [just_audio_web](https://pub.dev/packages/just_audio_web) | 0.4.16 | MIT |
| [latlong2](https://pub.dev/packages/latlong2) | 0.10.1 | Apache-2.0 |
| [leak_tracker](https://pub.dev/packages/leak_tracker) | 11.0.2 | BSD-3-Clause |
| [leak_tracker_flutter_testing](https://pub.dev/packages/leak_tracker_flutter_testing) | 3.0.10 | BSD-3-Clause |
| [leak_tracker_testing](https://pub.dev/packages/leak_tracker_testing) | 3.0.2 | BSD-3-Clause |
| [listen](https://pub.dev/packages/listen) | 1.0.1 | BSD-3-Clause |
| [logging](https://pub.dev/packages/logging) | 1.3.0 | BSD-3-Clause |
| [matcher](https://pub.dev/packages/matcher) | 0.12.20 | BSD-3-Clause |
| [material_color_utilities](https://pub.dev/packages/material_color_utilities) | 0.13.0 | Apache-2.0 |
| [meta](https://pub.dev/packages/meta) | 1.18.3 | BSD-3-Clause |
| [mgrs_dart](https://pub.dev/packages/mgrs_dart) | 3.0.0 | MIT |
| [mime](https://pub.dev/packages/mime) | 2.1.0 | BSD-3-Clause |
| [objective_c](https://pub.dev/packages/objective_c) | 9.5.0 | BSD-3-Clause |
| [package_config](https://pub.dev/packages/package_config) | 3.0.0 | BSD-3-Clause |
| [package_info_plus](https://pub.dev/packages/package_info_plus) | 10.2.2 | BSD-3-Clause |
| [package_info_plus_platform_interface](https://pub.dev/packages/package_info_plus_platform_interface) | 4.1.0 | BSD-3-Clause |
| [path](https://pub.dev/packages/path) | 1.9.1 | BSD-3-Clause |
| [path_provider](https://pub.dev/packages/path_provider) | 2.1.6 | BSD-3-Clause |
| [path_provider_android](https://pub.dev/packages/path_provider_android) | 2.3.1 | BSD-3-Clause |
| [path_provider_foundation](https://pub.dev/packages/path_provider_foundation) | 2.6.0 | BSD-3-Clause |
| [path_provider_linux](https://pub.dev/packages/path_provider_linux) | 2.2.2 | BSD-3-Clause |
| [path_provider_platform_interface](https://pub.dev/packages/path_provider_platform_interface) | 2.1.3 | BSD-3-Clause |
| [path_provider_windows](https://pub.dev/packages/path_provider_windows) | 2.3.0 | BSD-3-Clause |
| [petitparser](https://pub.dev/packages/petitparser) | 7.0.2 | MIT |
| [platform](https://pub.dev/packages/platform) | 3.2.0 | BSD-3-Clause |
| [plugin_platform_interface](https://pub.dev/packages/plugin_platform_interface) | 2.1.8 | BSD-3-Clause |
| [posix](https://pub.dev/packages/posix) | 6.5.4 | MIT |
| [proj4dart](https://pub.dev/packages/proj4dart) | 3.0.0 | MIT |
| [pub_semver](https://pub.dev/packages/pub_semver) | 2.2.1 | BSD-3-Clause |
| [record_use](https://pub.dev/packages/record_use) | 0.6.0 | BSD-3-Clause |
| [riverpod](https://pub.dev/packages/riverpod) | 3.4.3 | MIT |
| [rxdart](https://pub.dev/packages/rxdart) | 0.28.0 | Apache-2.0 |
| [share_plus](https://pub.dev/packages/share_plus) | 13.3.1 | BSD-3-Clause |
| [share_plus_platform_interface](https://pub.dev/packages/share_plus_platform_interface) | 7.2.0 | BSD-3-Clause |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 2.5.6 | BSD-3-Clause |
| [shared_preferences_android](https://pub.dev/packages/shared_preferences_android) | 2.5.4 | BSD-3-Clause |
| [shared_preferences_foundation](https://pub.dev/packages/shared_preferences_foundation) | 2.5.7 | BSD-3-Clause |
| [shared_preferences_linux](https://pub.dev/packages/shared_preferences_linux) | 2.4.1 | BSD-3-Clause |
| [shared_preferences_platform_interface](https://pub.dev/packages/shared_preferences_platform_interface) | 2.4.2 | BSD-3-Clause |
| [shared_preferences_web](https://pub.dev/packages/shared_preferences_web) | 2.4.3 | BSD-3-Clause |
| [shared_preferences_windows](https://pub.dev/packages/shared_preferences_windows) | 2.4.1 | BSD-3-Clause |
| [simple_sparse_list](https://pub.dev/packages/simple_sparse_list) | 0.1.4 | BSD-3-Clause |
| [source_span](https://pub.dev/packages/source_span) | 1.10.2 | BSD-3-Clause |
| [stack_trace](https://pub.dev/packages/stack_trace) | 1.12.2 | BSD-3-Clause |
| [state_notifier](https://pub.dev/packages/state_notifier) | 1.0.0 | MIT |
| [stream_channel](https://pub.dev/packages/stream_channel) | 2.1.4 | BSD-3-Clause |
| [string_scanner](https://pub.dev/packages/string_scanner) | 1.4.1 | BSD-3-Clause |
| [synchronized](https://pub.dev/packages/synchronized) | 3.5.0 | MIT |
| [term_glyph](https://pub.dev/packages/term_glyph) | 1.2.2 | BSD-3-Clause |
| [test_api](https://pub.dev/packages/test_api) | 0.7.12 | BSD-3-Clause |
| [typed_data](https://pub.dev/packages/typed_data) | 1.4.0 | BSD-3-Clause |
| [unicode](https://pub.dev/packages/unicode) | 1.1.9 | BSD-3-Clause |
| [url_launcher_linux](https://pub.dev/packages/url_launcher_linux) | 3.2.3 | BSD-3-Clause |
| [url_launcher_platform_interface](https://pub.dev/packages/url_launcher_platform_interface) | 2.3.2 | BSD-3-Clause |
| [url_launcher_web](https://pub.dev/packages/url_launcher_web) | 2.4.3 | BSD-3-Clause |
| [url_launcher_windows](https://pub.dev/packages/url_launcher_windows) | 3.1.6 | BSD-3-Clause |
| [uuid](https://pub.dev/packages/uuid) | 4.6.0 | MIT |
| [vector_math](https://pub.dev/packages/vector_math) | 2.4.0 | BSD-3-Clause |
| [vm_service](https://pub.dev/packages/vm_service) | 15.4.0 | BSD-3-Clause |
| [wakelock_plus](https://pub.dev/packages/wakelock_plus) | 1.8.2 | BSD-3-Clause |
| [wakelock_plus_platform_interface](https://pub.dev/packages/wakelock_plus_platform_interface) | 1.7.0 | BSD-3-Clause |
| [web](https://pub.dev/packages/web) | 1.1.2 | BSD-3-Clause |
| [win32](https://pub.dev/packages/win32) | 6.4.0 | BSD-3-Clause |
| [windows_file_picker](https://pub.dev/packages/windows_file_picker) | 2.0.1 | MIT |
| [wkt_parser](https://pub.dev/packages/wkt_parser) | 2.0.0 | MIT |
| [xdg_directories](https://pub.dev/packages/xdg_directories) | 1.1.0 | BSD-3-Clause |
| [xml](https://pub.dev/packages/xml) | 7.0.1 | MIT |
| [yaml](https://pub.dev/packages/yaml) | 3.1.4 | MIT |

## Nur für Tests und Entwicklung

Diese Pakete braucht nur `flutter test`; in der App sind sie nicht enthalten.

| Paket | Version | Lizenz |
|---|---|---|
| [flutter_lints](https://pub.dev/packages/flutter_lints) | 6.0.0 | BSD-3-Clause |
| [lints](https://pub.dev/packages/lints) | 6.1.0 | BSD-3-Clause |
| [mocktail](https://pub.dev/packages/mocktail) | 1.0.5 | MIT |
