import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/contracts/fixed_point_source.dart';
import 'limit_packages.dart';
import 'osm_source.dart';

/// Einstieg Modul OSM: feste Messstellen, Ampeln und Tempolimits aus Overpass mit Kachel-Cache.
FixedPointSource createOsmSource({
  required Directory cacheDir,
  http.Client? client,
  LimitPackages? limitPackages,
}) =>
    OsmSource(cacheDir: cacheDir, client: client, limitPackages: limitPackages);
