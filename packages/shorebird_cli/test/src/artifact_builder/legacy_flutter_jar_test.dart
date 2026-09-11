import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/legacy_flutter_jar.dart';
import 'package:test/test.dart';

void main() {
  group(LegacyFlutterJarReference, () {
    late Directory tmp;
    late Directory projectRoot;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync();
      projectRoot = Directory(p.join(tmp.path, 'app'))..createSync();
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    /// Creates a plugin directory with the given Android Gradle [buildGradle]
    /// contents and returns its path (for use in the manifest).
    String makePlugin({
      required String name,
      String? buildGradle,
      String buildGradleFileName = 'build.gradle',
    }) {
      final pluginRoot = Directory(p.join(tmp.path, 'plugins', name))
        ..createSync(recursive: true);
      final androidDir = Directory(p.join(pluginRoot.path, 'android'))
        ..createSync();
      if (buildGradle != null) {
        File(
          p.join(androidDir.path, buildGradleFileName),
        ).writeAsStringSync(buildGradle);
      }
      return '${pluginRoot.path}${p.separator}';
    }

    void writeManifest(List<Map<String, dynamic>> androidPlugins) {
      final entries = androidPlugins
          .map(
            (e) =>
                '''{"name": "${e['name']}", "path": "${(e['path'] as String).replaceAll(r'\', r'\\')}", "native_build": true, "dependencies": []}''',
          )
          .join(',');
      File(
        p.join(projectRoot.path, '.flutter-plugins-dependencies'),
      ).writeAsStringSync('{"plugins": {"android": [$entries]}}');
    }

    test('returns empty when the manifest is absent', () {
      expect(LegacyFlutterJarReference.findInProject(projectRoot), isEmpty);
    });

    test('returns empty when no plugin references flutter.jar', () {
      final path = makePlugin(
        name: 'connectivity_plus',
        buildGradle: "implementation 'androidx.core:core:1.0.0'",
      );
      writeManifest([
        {'name': 'connectivity_plus', 'path': path},
      ]);
      expect(LegacyFlutterJarReference.findInProject(projectRoot), isEmpty);
    });

    test('detects a plugin that references the legacy flutter.jar', () {
      final path = makePlugin(
        name: 'huawei_location',
        buildGradle:
            r'compileOnly files("$flutterRoot/bin/cache/artifacts/engine/android-arm/flutter.jar")',
      );
      writeManifest([
        {'name': 'huawei_location', 'path': path},
      ]);
      expect(LegacyFlutterJarReference.findInProject(projectRoot), [
        'huawei_location',
      ]);
    });

    test('detects references in build.gradle.kts', () {
      final path = makePlugin(
        name: 'legacy_kts',
        buildGradle: r'compileOnly(files("$flutterRoot/.../flutter.jar"))',
        buildGradleFileName: 'build.gradle.kts',
      );
      writeManifest([
        {'name': 'legacy_kts', 'path': path},
      ]);
      expect(LegacyFlutterJarReference.findInProject(projectRoot), [
        'legacy_kts',
      ]);
    });

    test('returns only the offending plugins among many', () {
      final clean = makePlugin(
        name: 'clean_plugin',
        buildGradle: 'implementation "com.example:lib:1.0"',
      );
      final legacy = makePlugin(
        name: 'huawei_location',
        buildGradle: 'compileOnly files("...flutter.jar")',
      );
      writeManifest([
        {'name': 'clean_plugin', 'path': clean},
        {'name': 'huawei_location', 'path': legacy},
      ]);
      expect(LegacyFlutterJarReference.findInProject(projectRoot), [
        'huawei_location',
      ]);
    });

    test('does not throw on a malformed manifest', () {
      File(
        p.join(projectRoot.path, '.flutter-plugins-dependencies'),
      ).writeAsStringSync('not valid json');
      expect(LegacyFlutterJarReference.findInProject(projectRoot), isEmpty);
    });

    test('recommendation lists each offending plugin', () {
      final recommendation = LegacyFlutterJarReference.recommendation([
        'huawei_location',
        'old_plugin',
      ]);
      expect(recommendation, contains('flutter.jar'));
      expect(recommendation, contains('• huawei_location'));
      expect(recommendation, contains('• old_plugin'));
    });
  });
}
