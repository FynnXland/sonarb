import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Ersatz, falls das Paket die Version nicht liefert (Tests, Desktop). Die Build-Skripte
/// setzen ihn per `--dart-define=SONARB_VERSION=…` auf den Wert aus pubspec.yaml.
const appVersionFallback = String.fromEnvironment(
  'SONARB_VERSION',
  defaultValue: '1.0.0',
);

/// Build-Nummer, falls das Paket sie nicht liefert (`--dart-define=SONARB_BUILD=…`).
const appBuildFallback = String.fromEnvironment('SONARB_BUILD');

/// „Version 1.0.0 (10)“, ohne bekannte Build-Nummer „Version 1.0.0“.
String versionLabel(String version, String build) =>
    build.isEmpty ? 'Version $version' : 'Version $version ($build)';

/// Ersatzzeile, solange das Paket noch nicht geantwortet hat.
final appVersionFallbackLabel = versionLabel(
  appVersionFallback,
  appBuildFallback,
);

/// Version und Build aus dem installierten Paket, also immer passend zu `version:` in
/// pubspec.yaml (Teil hinter dem Plus ist der Build).
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return versionLabel(
      info.version.isEmpty ? appVersionFallback : info.version,
      info.buildNumber.isEmpty ? appBuildFallback : info.buildNumber,
    );
  } catch (_) {
    return appVersionFallbackLabel;
  }
});
