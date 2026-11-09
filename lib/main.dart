import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/legal.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Diagnose nur in Debug- und Profil-Builds; im Release landet nichts im Systemprotokoll,
  // auch keine gesprochenen Sätze.
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
  registerDataLicenses();
  runApp(const ProviderScope(child: SonarbApp()));
}
