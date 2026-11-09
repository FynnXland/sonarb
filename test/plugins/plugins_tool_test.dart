import 'package:flutter_test/flutter_test.dart';

import '../../tool/plugins.dart';

void main() {
  group('generateInstalledPlugins', () {
    test('ohne Plugins: leere Liste, wie im Repository', () {
      final src = generateInstalledPlugins([]);
      expect(
        src,
        contains('List<DataSourcePlugin> installedPlugins() => const [];'),
      );
      expect(src, isNot(contains('local/')));
      expect(
        src,
        startsWith("import '../core/contracts/data_source_plugin.dart';"),
      );
    });

    test(
      'importiert jedes Plugin mit eigenem Alias und ruft createPlugin auf',
      () {
        final src = generateInstalledPlugins(['zeta', 'alpha']);
        expect(src, contains("import 'local/alpha/plugin.dart' as p0;"));
        expect(src, contains("import 'local/zeta/plugin.dart' as p1;"));
        expect(src, contains('p0.createPlugin(),'));
        expect(src, contains('p1.createPlugin(),'));
        expect(src, contains('List<DataSourcePlugin> installedPlugins() => ['));
        expect(src, isNot(contains('const [];')));
        expect(src, contains('GENERIERT'));
      },
    );

    test('ist deterministisch und entfernt Duplikate', () {
      expect(
        generateInstalledPlugins(['b', 'a', 'b']),
        generateInstalledPlugins(['a', 'b']),
      );
    });
  });

  group('declaresCreatePlugin', () {
    test('erkennt die Top-Level-Funktion', () {
      expect(
        declaresCreatePlugin('DataSourcePlugin createPlugin() => X();'),
        isTrue,
      );
      expect(
        declaresCreatePlugin(
          'import "a";\n\nDataSourcePlugin  createPlugin ( ) {\n}',
        ),
        isTrue,
      );
    });

    test('lehnt andere Signaturen und eingerückte Methoden ab', () {
      expect(declaresCreatePlugin('Foo createPlugin() => X();'), isFalse);
      expect(
        declaresCreatePlugin(
          'class A {\n  DataSourcePlugin createPlugin() => X();\n}',
        ),
        isFalse,
      );
      expect(declaresCreatePlugin(''), isFalse);
    });
  });

  test('isValidPluginDir lässt nur sichere Ordnernamen zu', () {
    expect(isValidPluginDir('mein-feed_2'), isTrue);
    expect(isValidPluginDir('a b'), isFalse);
    expect(isValidPluginDir("x';evil"), isFalse);
    expect(isValidPluginDir(''), isFalse);
  });
}
