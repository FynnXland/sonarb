import '../../core/contracts/warning_engine.dart';
import 'warning_engine_impl.dart';

/// Einstieg Modul Warnlogik. Signatur ist Vertrag mit `app/`.
WarningEngine createWarningEngine({
  WarningSettings settings = const WarningSettings(),
}) => DefaultWarningEngine(settings);
