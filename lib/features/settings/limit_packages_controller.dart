import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../cockpit/drive_controller.dart';
import '../osm/land_at.dart';
import '../osm/limit_download.dart';
import '../osm/limit_packages.dart';

/// Stand der Tempolimit-Pakete für die Einstellungen.
class LimitPackagesState {
  const LimitPackagesState({
    this.installed = const [],
    this.catalog,
    this.checking = false,
    this.unreachable = false,
    this.loading = const {},
    this.error,
  });

  final List<InstalledLimitPackage> installed;

  /// Angebot im Netz; null, solange es nicht abgerufen wurde.
  final List<LimitCatalogEntry>? catalog;
  final bool checking;

  /// Das Verzeichnis ließ sich nicht abrufen (kein Netz, oder die Adresse gibt es noch nicht).
  final bool unreachable;

  /// Kennung → Anteil 0–1 des laufenden Downloads.
  final Map<String, double> loading;
  final String? error;

  InstalledLimitPackage? installedFor(String id) =>
      installed.where((p) => p.id == id).firstOrNull;

  LimitPackagesState copyWith({
    List<InstalledLimitPackage>? installed,
    List<LimitCatalogEntry>? catalog,
    bool? checking,
    bool? unreachable,
    Map<String, double>? loading,
    String? error,
    bool clearError = false,
  }) => LimitPackagesState(
    installed: installed ?? this.installed,
    catalog: catalog ?? this.catalog,
    checking: checking ?? this.checking,
    unreachable: unreachable ?? this.unreachable,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Pakete laden, aktualisieren und löschen. Ruft das Netz nur auf Wunsch (Verzeichnis beim Öffnen
/// des Bildschirms, Paket auf Tipp); nichts läuft im Hintergrund oder während der Fahrt.
class LimitPackagesController extends Notifier<LimitPackagesState> {
  LimitPackages get _packages => ref.read(servicesProvider).limitPackages;
  LimitDownloader get _downloader => ref.read(servicesProvider).limitDownloader;

  @override
  LimitPackagesState build() {
    Future.microtask(readInstalled);
    return const LimitPackagesState();
  }

  Future<void> readInstalled() async {
    await _packages.ready;
    state = state.copyWith(installed: _packages.installed);
  }

  /// Fragt das Verzeichnis ab. Ein Fehler ist hier kein Fehler der App: der Bildschirm sagt nur
  /// „gerade nicht erreichbar“.
  Future<void> checkCatalog() async {
    if (state.checking) return;
    state = state.copyWith(checking: true, clearError: true);
    try {
      final catalog = await _downloader.catalog();
      state = state.copyWith(
        catalog: catalog,
        checking: false,
        unreachable: false,
      );
    } on LimitDownloadException {
      state = state.copyWith(checking: false, unreachable: true);
    }
  }

  Future<void> install(LimitCatalogEntry entry) async {
    if (state.loading.containsKey(entry.id)) return;
    state = state.copyWith(
      loading: {...state.loading, entry.id: 0},
      clearError: true,
    );
    String? error;
    try {
      await _downloader.download(
        entry,
        _packages,
        onProgress: (got, total) => state = state.copyWith(
          loading: {...state.loading, entry.id: total == 0 ? 0 : got / total},
        ),
      );
    } on LimitDownloadException catch (e) {
      error = switch (e.problem) {
        LimitDownloadProblem.unreachable =>
          '${entry.name}: Download nicht möglich. Nichts wurde geändert.',
        LimitDownloadProblem.tooBig ||
        LimitDownloadProblem.checksum ||
        LimitDownloadProblem.notAPackage =>
          '${entry.name}: Die Datei ist beschädigt und wurde verworfen.',
        LimitDownloadProblem.badCatalog =>
          '${entry.name}: Das Angebot ist unlesbar.',
      };
    }
    final loading = {...state.loading}..remove(entry.id);
    state = state.copyWith(
      installed: _packages.installed,
      loading: loading,
      error: error,
      clearError: error == null,
    );
  }

  Future<void> remove(String id) async {
    await _packages.remove(id);
    state = state.copyWith(installed: _packages.installed, clearError: true);
  }
}

final limitPackagesProvider =
    NotifierProvider<LimitPackagesController, LimitPackagesState>(
      LimitPackagesController.new,
    );

/// Kennung des Landes, in dem man gerade ist (grob, nur für den Vorschlag); null ohne Position.
final currentLandProvider = Provider<String?>((ref) {
  return ref.watch(
    driveControllerProvider.select((s) {
      final p = s.fix?.position;
      return p == null ? null : landAt(p.lat, p.lon);
    }),
  );
});

/// Das Paket, das die App vorschlägt: das des aktuellen Landes, solange noch keines installiert ist
/// und das Angebot abgerufen wurde.
final limitSuggestionProvider = Provider<LimitCatalogEntry?>((ref) {
  final state = ref.watch(limitPackagesProvider);
  final land = ref.watch(currentLandProvider);
  if (land == null || state.installed.isNotEmpty) return null;
  return state.catalog?.where((e) => e.id == land).firstOrNull;
});
