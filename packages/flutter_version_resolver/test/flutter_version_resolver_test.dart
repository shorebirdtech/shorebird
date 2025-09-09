import 'dart:io';

import 'package:flutter_version_resolver/flutter_version_resolver.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  late Logger logger;
  late Directory packageDirectory;
  late File pubspecFile;

  setUp(() {
    logger = _MockLogger();

    packageDirectory = Directory.systemTemp.createTempSync(
      'flutter_version_resolver_test',
    );
    pubspecFile = File(
      p.join(packageDirectory.path, 'pubspec.yaml'),
    )..writeAsStringSync('name: flutter_version_resolver_test');
  });

  group('resolveFlutterVersion', () {
    group('when no flutter version is specified in the pubspec.yaml', () {
      test('returns the stable version', () {
        expect(
          resolveFlutterVersion(
            packagePath: packageDirectory.path,
            log: logger.info,
          ),
          equals('stable'),
        );
      });
    });

    group('when a flutter version is specified in the pubspec.yaml', () {
      setUp(() {
        pubspecFile.writeAsStringSync('''
environment:
  sdk: ^3.8.1
  flutter: 3.20.0
''');
      });

      test('returns the version', () {
        expect(
          resolveFlutterVersion(
            packagePath: packageDirectory.path,
            log: logger.info,
          ),
          equals('3.20.0'),
        );
      });
    });

    group('when a version constraint is specified in the pubspec.yaml', () {
      setUp(() {
        pubspecFile.writeAsStringSync('''
environment:
  sdk: ^3.8.1
  flutter: "^3.8.0"
''');
      });

      test('prints an error message and returns the stable version', () {
        expect(
          resolveFlutterVersion(
            packagePath: packageDirectory.path,
            log: logger.info,
          ),
          equals('stable'),
        );
        verify(
          () => logger.info(
            '''Found version constraint: ^3.8.0. Version constraints are not supported in pubspec.yaml. Please specify a specific version.''',
          ),
        ).called(1);
      });
    });
  });

  group('flutterVersionFromPubspecEnvironment', () {
    group('when no pubspec.yaml is found', () {
      test('throws an exception', () {
        expect(
          () => flutterVersionFromPubspecEnvironment(
            packagePath: 'no/such/package',
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('when no flutter version is specified', () {
      test('returns null', () {
        expect(
          flutterVersionFromPubspecEnvironment(
            packagePath: packageDirectory.path,
          ),
          isNull,
        );
      });
    });

    group('when a flutter version range is specified', () {
      setUp(() {
        pubspecFile.writeAsStringSync('''
environment:
  sdk: ^3.8.1
  flutter: ">=3.8.0 <4.0.0"
''');
      });

      test('throws a VersionConstraintException', () {
        expect(
          () => flutterVersionFromPubspecEnvironment(
            packagePath: packageDirectory.path,
          ),
          throwsA(isA<VersionConstraintException>()),
        );
      });
    });

    group('when a minimum version is specified', () {
      setUp(() {
        pubspecFile.writeAsStringSync('''
environment:
  sdk: ^3.8.1
  flutter: "^3.8.0"
''');
      });

      test('throws a VersionConstraintException', () {
        expect(
          () => flutterVersionFromPubspecEnvironment(
            packagePath: packageDirectory.path,
          ),
          throwsA(isA<VersionConstraintException>()),
        );
      });
    });

    group('when a flutter version is specified', () {
      setUp(() {
        pubspecFile.writeAsStringSync('''
environment:
  sdk: ^3.8.1
  flutter: 3.20.0
''');
      });

      test('returns the version', () {
        expect(
          flutterVersionFromPubspecEnvironment(
            packagePath: packageDirectory.path,
          ),
          equals(Version(3, 20, 0)),
        );
      });
    });
  });
}
