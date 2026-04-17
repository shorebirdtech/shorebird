import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/build_environment.dart';
import 'package:test/test.dart';

void main() {
  group(BuildEnvironment, () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync());
    tearDown(() => tmp.deleteSync(recursive: true));

    Directory makeProjectRoot({String? gradleProperties}) {
      final root = Directory(p.join(tmp.path, 'app'))..createSync();
      Directory(p.join(root.path, 'android')).createSync();
      if (gradleProperties != null) {
        File(
          p.join(root.path, 'android', 'gradle.properties'),
        ).writeAsStringSync(gradleProperties);
      }
      return root;
    }

    Directory makeHome({String? gradleProperties, String? initScript}) {
      final home = Directory(p.join(tmp.path, 'home'))..createSync();
      final gradleDir = Directory(p.join(home.path, '.gradle'))..createSync();
      if (gradleProperties != null) {
        File(
          p.join(gradleDir.path, 'gradle.properties'),
        ).writeAsStringSync(gradleProperties);
      }
      if (initScript != null) {
        Directory(p.join(gradleDir.path, 'init.d')).createSync();
        File(
          p.join(gradleDir.path, 'init.d', 'develocity.gradle'),
        ).writeAsStringSync(initScript);
      }
      return home;
    }

    test('default empty env → all caching disabled, no CI', () {
      final env = BuildEnvironment.detect(
        environment: const <String, String>{},
        homeDir: tmp,
        projectRoot: tmp,
      );
      expect(env.isCi, isFalse);
      expect(env.ciProvider, isNull);
      expect(env.gradleBuildCacheEnabled, isFalse);
      expect(env.gradleConfigurationCacheEnabled, isFalse);
      expect(env.gradleParallelEnabled, isFalse);
      expect(env.gradleDaemonEnabled, isTrue); // default-on
      expect(env.gradleDevelocityDetected, isFalse);
      expect(env.gradleInitScriptCount, 0);
      expect(env.iosCcacheAvailable, isFalse);
    });

    test('reads project gradle.properties for cache + parallel', () {
      final root = makeProjectRoot(
        gradleProperties: '''
# Comment line, ignored
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.daemon=false
org.gradle.configuration-cache=true
''',
      );
      final env = BuildEnvironment.detect(
        environment: const <String, String>{},
        homeDir: tmp,
        projectRoot: root,
      );
      expect(env.gradleBuildCacheEnabled, isTrue);
      expect(env.gradleParallelEnabled, isTrue);
      expect(env.gradleDaemonEnabled, isFalse);
      expect(env.gradleConfigurationCacheEnabled, isTrue);
    });

    test('detects Develocity init script', () {
      final home = makeHome(
        initScript: 'apply(plugin: "com.gradle.develocity")',
      );
      final env = BuildEnvironment.detect(
        environment: const <String, String>{},
        homeDir: home,
        projectRoot: tmp,
      );
      expect(env.gradleDevelocityDetected, isTrue);
      expect(env.gradleInitScriptCount, 1);
    });

    test('detects legacy com.gradle.enterprise marker', () {
      final home = makeHome(
        initScript: 'apply(plugin: "com.gradle.enterprise")',
      );
      final env = BuildEnvironment.detect(
        environment: const <String, String>{},
        homeDir: home,
        projectRoot: tmp,
      );
      expect(env.gradleDevelocityDetected, isTrue);
    });

    test('detects develocity { ... } block in project settings.gradle.kts', () {
      final root = Directory(p.join(tmp.path, 'proj'))..createSync();
      Directory(p.join(root.path, 'android')).createSync();
      File(
        p.join(root.path, 'android', 'settings.gradle.kts'),
      ).writeAsStringSync('develocity {\n  server = "..."\n}\n');
      final env = BuildEnvironment.detect(
        environment: const <String, String>{},
        homeDir: tmp,
        projectRoot: root,
      );
      expect(env.gradleDevelocityDetected, isTrue);
    });

    test('detects gradleEnterprise { ... } block in settings.gradle', () {
      final root = Directory(p.join(tmp.path, 'proj2'))..createSync();
      Directory(p.join(root.path, 'android')).createSync();
      File(
        p.join(root.path, 'android', 'settings.gradle'),
      ).writeAsStringSync('gradleEnterprise {\n}\n');
      final env = BuildEnvironment.detect(
        environment: const <String, String>{},
        homeDir: tmp,
        projectRoot: root,
      );
      expect(env.gradleDevelocityDetected, isTrue);
    });

    test('recognizes .gradle.kts init scripts under ~/.gradle/init.d', () {
      final home = Directory(p.join(tmp.path, 'home2'))..createSync();
      final initDir = Directory(p.join(home.path, '.gradle', 'init.d'))
        ..createSync(recursive: true);
      File(
        p.join(initDir.path, 'develocity.gradle.kts'),
      ).writeAsStringSync('develocity {\n}\n');
      final env = BuildEnvironment.detect(
        environment: const <String, String>{},
        homeDir: home,
        projectRoot: tmp,
      );
      expect(env.gradleDevelocityDetected, isTrue);
      expect(env.gradleInitScriptCount, 1);
    });

    test('classifies common CI providers', () {
      expect(
        BuildEnvironment.detect(
          environment: const <String, String>{'GITHUB_ACTIONS': 'true'},
        ).ciProvider,
        'github',
      );
      expect(
        BuildEnvironment.detect(
          environment: const <String, String>{'CI': 'true'},
        ).ciProvider,
        'other',
      );
      expect(
        BuildEnvironment.detect(
          environment: const <String, String>{'CIRCLECI': 'true'},
        ).ciProvider,
        'circle',
      );
    });

    test('toJson is privacy-safe (only bool/int/enum-string)', () {
      final env = BuildEnvironment.detect(
        environment: const <String, String>{'GITHUB_ACTIONS': 'true'},
      );
      final j = env.toJson();
      void checkLeaf(Object? v) {
        expect(
          v,
          anyOf(isA<bool>(), isA<int>(), isA<String>(), isNull),
          reason: 'leaf $v not a privacy-safe scalar',
        );
        // String leaves are limited to small enums.
        if (v is String) {
          expect(v.length, lessThan(40));
          expect(v.contains('/'), isFalse);
          expect(v.contains(r'\'), isFalse);
        }
      }

      void walk(Object? node) {
        if (node is Map) {
          node.values.forEach(walk);
        } else {
          checkLeaf(node);
        }
      }

      walk(j);
    });
  });
}
