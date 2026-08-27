// cspell:words revis
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(ShorebirdFlutter, () {
    const flutterRevision = 'flutter-revision';
    late Directory shorebirdRoot;
    late Directory flutterDirectory;
    late Git git;
    late ShorebirdLogger logger;
    late Platform platform;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdEnv targetShorebirdEnv;
    late ShorebirdProcess process;
    late ShorebirdProcessResult versionProcessResult;
    late ShorebirdProcessResult precacheProcessResult;
    late ShorebirdFlutter shorebirdFlutter;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          gitRef.overrideWith(() => git),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(p.join(shorebirdRoot.path, 'flutter'));
      git = MockGit();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      targetShorebirdEnv = MockShorebirdEnv();
      platform = MockPlatform();
      process = MockShorebirdProcess();
      versionProcessResult = MockShorebirdProcessResult();
      precacheProcessResult = MockShorebirdProcessResult();
      shorebirdFlutter = runWithOverrides(ShorebirdFlutter.new);

      when(
        () => git.clone(
          url: any(named: 'url'),
          outputDirectory: any(named: 'outputDirectory'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((invocation) async {
        // Real `git clone` creates the output directory; installRevision
        // writes into it afterwards.
        Directory(
          invocation.namedArguments[#outputDirectory] as String,
        ).createSync(recursive: true);
      });
      when(
        () => git.checkout(
          directory: any(named: 'directory'),
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => git.status(
          directory: p.join(flutterDirectory.parent.path, flutterRevision),
          args: ['--untracked-files=no', '--porcelain'],
        ),
      ).thenAnswer((_) async => '');
      when(
        () => git.fetch(directory: any(named: 'directory')),
      ).thenAnswer((_) async {});
      when(
        () => git.revParse(
          revision: any(named: 'revision'),
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => flutterRevision);
      when(
        () => git.forEachRef(
          directory: any(named: 'directory'),
          contains: any(named: 'contains'),
          format: any(named: 'format'),
          pattern: any(named: 'pattern'),
        ),
      ).thenAnswer((_) async => 'origin/flutter_release/3.10.6');
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdEnv.copyWith(
          flutterRevisionOverride: any(named: 'flutterRevisionOverride'),
        ),
      ).thenAnswer((invocation) {
        when(() => targetShorebirdEnv.flutterRevision).thenReturn(
          invocation.namedArguments[#flutterRevisionOverride] as String,
        );
        return targetShorebirdEnv;
      });
      when(
        () => process.run('flutter', ['--version'], useVendedFlutter: false),
      ).thenAnswer((_) async => versionProcessResult);
      when(() => versionProcessResult.exitCode).thenReturn(0);
      when(
        () => process.run(
          'flutter',
          any(that: contains('precache')),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => precacheProcessResult);
      when(
        () => precacheProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(() => precacheProcessResult.stderr).thenReturn('');
    });

    group('precacheArgs', () {
      group('when running on macOS', () {
        setUp(() {
          when(() => platform.isMacOS).thenReturn(true);
        });

        test('includes ios in platform list', () async {
          expect(
            runWithOverrides(() => shorebirdFlutter.precacheArgs),
            contains('--ios'),
          );
        });
      });

      group('when not running on macOS', () {
        setUp(() {
          when(() => platform.isMacOS).thenReturn(false);
        });

        test('does not include ios in platform list', () {
          expect(
            runWithOverrides(() => shorebirdFlutter.precacheArgs),
            isNot(contains('--ios')),
          );
        });
      });
    });

    group('getConfig', () {
      late ShorebirdProcessResult configProcessResult;

      setUp(() {
        configProcessResult = MockProcessResult();
        when(
          () => process.runSync(any(), any()),
        ).thenReturn(configProcessResult);
      });

      group('when process exists with non-zero code', () {
        setUp(() {
          when(
            () => configProcessResult.exitCode,
          ).thenReturn(ExitCode.software.code);
          when(() => configProcessResult.stderr).thenReturn('oops');
        });

        test('returns empty map', () {
          expect(runWithOverrides(shorebirdFlutter.getConfig), isEmpty);
          verify(
            () => process.runSync('flutter', ['config', '--list']),
          ).called(1);
        });
      });

      group('when process completes successfully', () {
        setUp(() {
          when(() => configProcessResult.stdout).thenReturn(r'''
All Settings:
  enable-web: (Not set)
  enable-linux-desktop: (Not set)
  enable-macos-desktop: (Not set)
  enable-windows-desktop: (Not set)
  enable-android: (Not set)
  enable-ios: (Not set)
  enable-fuchsia: (Not set) (Unavailable)
  enable-custom-devices: (Not set)
  cli-animations: (Not set)
  enable-native-assets: (Not set) (Unavailable)
  enable-flutter-preview: (Not set) (Unavailable)
  enable-swift-package-manager: (Not set)
  explicit-package-dependencies: (Not set)
  jdk-dir: C:\Program Files\Android\Android Studio\jdk
  ''');
          when(
            () => configProcessResult.exitCode,
          ).thenReturn(ExitCode.success.code);
        });

        test('returns correct config map', () {
          expect(
            runWithOverrides(shorebirdFlutter.getConfig),
            equals({
              'enable-web': '(Not set)',
              'enable-linux-desktop': '(Not set)',
              'enable-macos-desktop': '(Not set)',
              'enable-windows-desktop': '(Not set)',
              'enable-android': '(Not set)',
              'enable-ios': '(Not set)',
              'enable-fuchsia': '(Not set) (Unavailable)',
              'enable-custom-devices': '(Not set)',
              'cli-animations': '(Not set)',
              'enable-native-assets': '(Not set) (Unavailable)',
              'enable-flutter-preview': '(Not set) (Unavailable)',
              'enable-swift-package-manager': '(Not set)',
              'explicit-package-dependencies': '(Not set)',
              'jdk-dir': r'C:\Program Files\Android\Android Studio\jdk',
            }),
          );
        });
      });
    });

    group('getSystemVersion', () {
      test(
        'throws ProcessException when process exits with non-zero code',
        () async {
          const error = 'oops';
          when(
            () => versionProcessResult.exitCode,
          ).thenReturn(ExitCode.software.code);
          when(() => versionProcessResult.stderr).thenReturn(error);
          await expectLater(
            runWithOverrides(shorebirdFlutter.getSystemVersion),
            throwsA(isA<ProcessException>()),
          );
          verify(
            () =>
                process.run('flutter', ['--version'], useVendedFlutter: false),
          ).called(1);
        },
      );

      test('returns null when cannot parse version', () async {
        when(() => versionProcessResult.stdout).thenReturn('');
        await expectLater(
          runWithOverrides(shorebirdFlutter.getSystemVersion),
          completion(isNull),
        );
        verify(
          () => process.run('flutter', ['--version'], useVendedFlutter: false),
        ).called(1);
      });

      test('returns version when able to parse the string', () async {
        when(() => versionProcessResult.stdout).thenReturn('''
Flutter 3.10.6 • channel stable • git@github.com:flutter/flutter.git
Framework • revision f468f3366c (4 weeks ago) • 2023-07-12 15:19:05 -0700
Engine • revision cdbeda788a
Tools • Dart 3.0.6 • DevTools 2.23.1''');
        await expectLater(
          runWithOverrides(shorebirdFlutter.getSystemVersion),
          completion(equals('3.10.6')),
        );
        verify(
          () => process.run('flutter', ['--version'], useVendedFlutter: false),
        ).called(1);
      });
    });

    group('getVersionAndRevision', () {
      group('when unable to determine version', () {
        const error = 'oops';
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenThrow(
            ProcessException(
              'git',
              [
                'for-each-ref',
                '--format',
                '%(refname:short)',
                'refs/remotes/origin/flutter_release/*',
              ],
              error,
              ExitCode.software.code,
            ),
          );
        });

        test('returns unknown (<revision>)', () async {
          await expectLater(
            runWithOverrides(shorebirdFlutter.getVersionAndRevision),
            completion(equals('unknown (${flutterRevision.substring(0, 10)})')),
          );
        });
      });

      test('returns correct version and revision', () async {
        await expectLater(
          runWithOverrides(shorebirdFlutter.getVersionAndRevision),
          completion(equals('3.10.6 (${flutterRevision.substring(0, 10)})')),
        );
      });
    });

    group('resolveFlutterRevision', () {
      group('when input is a semver version', () {
        test(
          'returns the revision associated with the version if it exists',
          () async {
            final revision = await runWithOverrides(
              () => shorebirdFlutter.resolveFlutterRevision('3.10.6'),
            );
            expect(revision, equals(flutterRevision));
          },
        );
      });

      group('when input is a valid git hash that exists locally', () {
        const fullHash = 'eead750584a909f506eb6fc111ece5d8fed4aa39';

        setUp(() {
          when(
            () => git.revParse(
              revision: any(named: 'revision'),
              directory: any(named: 'directory'),
            ),
          ).thenAnswer((_) async => fullHash);
        });

        test('returns full hash for full input', () async {
          final revision = await runWithOverrides(
            () => shorebirdFlutter.resolveFlutterRevision(fullHash),
          );
          expect(revision, equals(fullHash));
        });

        test('returns full hash for short input', () async {
          final revision = await runWithOverrides(
            () => shorebirdFlutter.resolveFlutterRevision('deadbeef'),
          );
          expect(revision, equals(fullHash));
        });
      });

      group('when input is a valid git hash format but does not exist', () {
        setUp(() {
          when(
            () => git.revParse(
              revision: any(named: 'revision'),
              directory: any(named: 'directory'),
            ),
          ).thenThrow(
            const ProcessException('git', ['rev-parse']),
          );
        });

        test('returns null', () async {
          const validHash = 'eead750584a909f506eb6fc111ece5d8fed4aa39';
          final revision = await runWithOverrides(
            () => shorebirdFlutter.resolveFlutterRevision(validHash),
          );
          expect(revision, isNull);
        });
      });

      group('when input is not a valid git hash format', () {
        test('returns null for too-short hash', () async {
          final revision = await runWithOverrides(
            () => shorebirdFlutter.resolveFlutterRevision('abc'),
          );
          expect(revision, isNull);
        });

        test('returns null for non-hex string', () async {
          final revision = await runWithOverrides(
            () => shorebirdFlutter.resolveFlutterRevision('not-a-version'),
          );
          expect(revision, isNull);
        });
      });
    });

    group('resolveFlutterVersion', () {
      group('when input is a semver version', () {
        test(
          'returns the revision associated with the version if it exists',
          () async {
            final revision = await runWithOverrides(
              () => shorebirdFlutter.resolveFlutterVersion('3.10.6'),
            );
            expect(revision, equals(Version(3, 10, 6)));
          },
        );
      });

      group('when input is not a recognized commit hash', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => '');
        });

        test('returns null', () async {
          final revision = await runWithOverrides(
            () => shorebirdFlutter.resolveFlutterVersion('not-a-version'),
          );
          expect(revision, isNull);
        });
      });

      group('when commit lookup fails', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('returns null', () async {
          final revision = await runWithOverrides(
            () => shorebirdFlutter.resolveFlutterVersion('not-a-version'),
          );
          expect(revision, isNull);
        });
      });

      group('when input is a recognized commit hash', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => 'origin/flutter_release/1.2.3');
        });

        test('returns a parsed version', () async {
          final revision = await runWithOverrides(
            () => shorebirdFlutter.resolveFlutterVersion('deadbeef'),
          );
          expect(revision, equals(Version(1, 2, 3)));
        });
      });
    });

    group('shouldPreStripLibappInGenSnapshot', () {
      test('returns true on iOS regardless of Flutter version', () async {
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            contains: any(named: 'contains'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenAnswer((_) async => 'origin/flutter_release/3.44.0');

        final result = await runWithOverrides(
          () => shorebirdFlutter.shouldPreStripLibappInGenSnapshot(
            platform: ReleasePlatform.ios,
            flutterRevision: 'deadbeef',
          ),
        );
        expect(result, isTrue);
      });

      test('returns true on Android when Flutter is older than 3.44', () async {
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            contains: any(named: 'contains'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenAnswer((_) async => 'origin/flutter_release/3.43.0');

        final result = await runWithOverrides(
          () => shorebirdFlutter.shouldPreStripLibappInGenSnapshot(
            platform: ReleasePlatform.android,
            flutterRevision: 'deadbeef',
          ),
        );
        expect(result, isTrue);
      });

      test('returns false on Android when Flutter is 3.44 or newer', () async {
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            contains: any(named: 'contains'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenAnswer((_) async => 'origin/flutter_release/3.44.0');

        final result = await runWithOverrides(
          () => shorebirdFlutter.shouldPreStripLibappInGenSnapshot(
            platform: ReleasePlatform.android,
            flutterRevision: 'deadbeef',
          ),
        );
        expect(result, isFalse);
      });

      test(
        '''returns false on Android when the version cannot be resolved (development pin)''',
        () async {
          // Unresolvable revisions (e.g. development branches) fall back to the
          // constraint's min version, so users on bleeding-edge pins get the
          // 3.44+ AGP-stripped behavior rather than the pre-strip path.
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => '');

          final result = await runWithOverrides(
            () => shorebirdFlutter.shouldPreStripLibappInGenSnapshot(
              platform: ReleasePlatform.android,
              flutterRevision: 'deadbeef',
            ),
          );
          expect(result, isFalse);
        },
      );
    });

    group('fetchRemoteRefs', () {
      test('fetches from remote', () async {
        when(
          () => git.fetch(directory: any(named: 'directory')),
        ).thenAnswer((_) async {});

        await runWithOverrides(
          () => shorebirdFlutter.fetchRemoteRefs(),
        );

        verify(
          () => git.fetch(directory: any(named: 'directory')),
        ).called(1);
      });

      group('when fetch fails', () {
        setUp(() {
          when(
            () => git.fetch(directory: any(named: 'directory')),
          ).thenThrow(Exception('no network'));
        });

        test('logs a warning', () async {
          await runWithOverrides(
            () => shorebirdFlutter.fetchRemoteRefs(),
          );

          verify(
            () => logger.warn(any(that: contains('stale'))),
          ).called(1);
        });
      });
    });

    group('getRevisionForVersion', () {
      const version = '3.16.3';
      const exception = ProcessException('git', ['rev-parse']);

      group('when process exits with non-zero code', () {
        setUp(() {
          when(
            () => git.revParse(
              revision: any(named: 'revision'),
              directory: any(named: 'directory'),
            ),
          ).thenThrow(exception);
        });

        test('returns null', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.getRevisionForVersion(version),
            ),
            completion(isNull),
          );
          verify(
            () => git.revParse(
              revision: 'refs/remotes/origin/flutter_release/$version',
              directory: any(named: 'directory'),
            ),
          ).called(1);
        });
      });

      group('when cannot parse revision', () {
        setUp(() {
          when(
            () => git.revParse(
              revision: any(named: 'revision'),
              directory: any(named: 'directory'),
            ),
          ).thenAnswer((_) async => '');
        });

        test('returns null', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.getRevisionForVersion(version),
            ),
            completion(isNull),
          );
          verify(
            () => git.revParse(
              revision: 'refs/remotes/origin/flutter_release/$version',
              directory: any(named: 'directory'),
            ),
          ).called(1);
        });
      });

      group('when able to parse the string', () {
        const revision = '771d07b2cf97cf107bae6eeedcf41bdc9db772fa';
        setUp(() {
          when(
            () => git.revParse(
              revision: any(named: 'revision'),
              directory: any(named: 'directory'),
            ),
          ).thenAnswer(
            (_) async =>
                '''
$revision
        ''',
          );
        });

        test('returns revision', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.getRevisionForVersion(version),
            ),
            completion(equals(revision)),
          );
          verify(
            () => git.revParse(
              revision: 'refs/remotes/origin/flutter_release/$version',
              directory: any(named: 'directory'),
            ),
          ).called(1);
        });
      });
    });

    group('getVersionString', () {
      group('when process exits with non-zero code', () {
        const error = 'oops';

        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenThrow(
            ProcessException(
              'git',
              [
                'for-each-ref',
                '--format',
                '%(refname:short)',
                'refs/remotes/origin/flutter_release/*',
              ],
              error,
              ExitCode.software.code,
            ),
          );
        });

        test('throws ProcessException', () async {
          await expectLater(
            runWithOverrides(shorebirdFlutter.getVersionString),
            throwsA(isA<ProcessException>()),
          );
          verify(
            () => git.forEachRef(
              directory: p.join(flutterDirectory.parent.path, flutterRevision),
              contains: flutterRevision,
              format: '%(refname:short)',
              pattern: 'refs/remotes/origin/flutter_release/*',
            ),
          ).called(1);
        });
      });

      group('when cannot parse version', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => '');
        });

        test('returns null', () async {
          await expectLater(
            runWithOverrides(shorebirdFlutter.getVersionString),
            completion(isNull),
          );
          verify(
            () => git.forEachRef(
              directory: p.join(flutterDirectory.parent.path, flutterRevision),
              contains: flutterRevision,
              format: '%(refname:short)',
              pattern: 'refs/remotes/origin/flutter_release/*',
            ),
          ).called(1);
        });
      });

      group('when able to parse the string', () {
        test('returns version', () async {
          await expectLater(
            runWithOverrides(shorebirdFlutter.getVersionString),
            completion(equals('3.10.6')),
          );
          verify(
            () => git.forEachRef(
              directory: p.join(flutterDirectory.parent.path, flutterRevision),
              contains: flutterRevision,
              format: '%(refname:short)',
              pattern: 'refs/remotes/origin/flutter_release/*',
            ),
          ).called(1);
        });
      });
    });

    group('getVersion', () {
      group('when getVersionString returns null', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => '');
        });

        test('returns null', () {
          expect(
            runWithOverrides(shorebirdFlutter.getVersion),
            completion(isNull),
          );
        });
      });

      group('when getVersionString returns an invalid string', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => 'not a version');
        });

        test('returns null', () {
          expect(
            runWithOverrides(shorebirdFlutter.getVersion),
            completion(isNull),
          );
        });
      });

      group('when getVersionString returns a valid string', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => '3.10.6');
        });

        test('returns the version', () {
          expect(
            runWithOverrides(shorebirdFlutter.getVersion),
            completion(equals(Version(3, 10, 6))),
          );
        });
      });
    });

    group('getVersions', () {
      const format = '%(refname:short)';
      const pattern = 'refs/remotes/origin/flutter_release/*';
      test('returns a list of versions', () async {
        const versions = [
          '3.10.0',
          '3.10.1',
          '3.10.2',
          '3.10.3',
          '3.10.4',
          '3.10.5',
          '3.10.6',
        ];
        const output = '''
origin/flutter_release/3.10.0
origin/flutter_release/3.10.1
origin/flutter_release/3.10.2
origin/flutter_release/3.10.3
origin/flutter_release/3.10.4
origin/flutter_release/3.10.5
origin/flutter_release/3.10.6''';
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenAnswer((_) async => output);

        await expectLater(
          runWithOverrides(shorebirdFlutter.getVersions),
          completion(equals(versions)),
        );
        verify(
          () => git.forEachRef(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            format: format,
            pattern: pattern,
          ),
        ).called(1);
      });

      test(
        'throws ProcessException when git command exits non-zero code',
        () async {
          const errorMessage = 'oh no!';
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenThrow(
            ProcessException(
              'git',
              ['for-each-ref', '--format', format, pattern],
              errorMessage,
              ExitCode.software.code,
            ),
          );

          expect(
            runWithOverrides(shorebirdFlutter.getVersions),
            throwsA(
              isA<ProcessException>().having(
                (e) => e.message,
                'message',
                errorMessage,
              ),
            ),
          );
        },
      );
    });

    group('installRevision', () {
      const revision = 'test-revision';
      late Directory targetDirectory;
      late File precacheStamp;

      /// Puts [targetDirectory] in the state left by a published checkout,
      /// without the precache stamp.
      void createCheckout() => targetDirectory.createSync(recursive: true);

      setUp(() {
        targetDirectory = Directory(
          p.join(flutterDirectory.parent.path, revision),
        );
        precacheStamp = File(
          p.join(targetDirectory.path, ShorebirdFlutter.precacheStampName),
        );
      });

      test('does nothing if the revision is already installed', () async {
        createCheckout();
        precacheStamp.createSync();

        await runWithOverrides(
          () => shorebirdFlutter.installRevision(revision: revision),
        );

        verifyNever(
          () => git.clone(
            url: any(named: 'url'),
            outputDirectory: any(named: 'outputDirectory'),
            args: any(named: 'args'),
          ),
        );
        verifyNever(
          () => process.run(
            'flutter',
            any(that: contains('precache')),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        );
      });

      group('when the checkout completed but precache did not', () {
        setUp(createCheckout);

        test('precaches without re-cloning', () async {
          await runWithOverrides(
            () => shorebirdFlutter.installRevision(revision: revision),
          );

          verifyNever(
            () => git.clone(
              url: any(named: 'url'),
              outputDirectory: any(named: 'outputDirectory'),
              args: any(named: 'args'),
            ),
          );
          verify(
            () => process.run(
              'flutter',
              any(that: contains('precache')),
              workingDirectory: targetDirectory.path,
            ),
          ).called(1);
          expect(precacheStamp.existsSync(), isTrue);
        });
      });

      test('clones and checks out away from the target directory', () async {
        late String cloneDirectory;
        when(
          () => git.clone(
            url: any(named: 'url'),
            outputDirectory: any(named: 'outputDirectory'),
            args: any(named: 'args'),
          ),
        ).thenAnswer((invocation) async {
          cloneDirectory =
              invocation.namedArguments[#outputDirectory] as String;
          Directory(cloneDirectory).createSync(recursive: true);
        });

        await runWithOverrides(
          () => shorebirdFlutter.installRevision(revision: revision),
        );

        // The target directory must never hold an in-progress checkout, so
        // that its existence is proof of a finished one.
        expect(cloneDirectory, isNot(targetDirectory.path));
        verify(
          () => git.checkout(directory: cloneDirectory, revision: revision),
        ).called(1);
        expect(Directory(cloneDirectory).existsSync(), isFalse);
        expect(targetDirectory.existsSync(), isTrue);
        // A clean install has no cleanup to report; saying otherwise would
        // put a failure line in the log support asks users to attach.
        verifyNever(
          () => logger.detail(any(that: contains('Failed to remove'))),
        );
      });

      group('when an earlier install was killed before publishing', () {
        late Directory strandedStaging;

        setUp(() {
          strandedStaging = Directory('${targetDirectory.path}.9999.tmp')
            ..createSync(recursive: true);
        });

        test('reclaims the stranded staging directory', () async {
          // The sweep runs over every sibling of the target, so the name
          // filter is all that keeps it off other installs.
          final otherInstall = Directory(
            p.join(flutterDirectory.parent.path, 'another-revision'),
          )..createSync(recursive: true);
          final notStaging = Directory('${targetDirectory.path}.notstaging')
            ..createSync(recursive: true);
          // Another revision's staging directory. Each install reclaims only
          // its own strays, so this one is not ours to remove.
          final otherStaging = Directory(
            p.join(flutterDirectory.parent.path, 'another-revision.9999.tmp'),
          )..createSync(recursive: true);

          // A stranded directory is only distinguishable from a concurrent
          // install's by how long it has sat untouched.
          await withClock(
            Clock.fixed(DateTime.now().add(const Duration(days: 2))),
            () => runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            ),
          );

          expect(strandedStaging.existsSync(), isFalse);
          expect(otherInstall.existsSync(), isTrue);
          expect(notStaging.existsSync(), isTrue);
          expect(otherStaging.existsSync(), isTrue);
          expect(targetDirectory.existsSync(), isTrue);
        });

        test(
          'leaves a concurrent install\'s staging directory alone',
          () async {
            await runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            );

            expect(strandedStaging.existsSync(), isTrue);
          },
        );
      });

      group('when nothing has been installed yet', () {
        setUp(() {
          // No cache directory at all, so there are no siblings to sweep.
          when(() => shorebirdEnv.flutterDirectory).thenReturn(
            Directory(p.join(shorebirdRoot.path, 'missing', flutterRevision)),
          );
          targetDirectory = Directory(
            p.join(shorebirdRoot.path, 'missing', revision),
          );
        });

        test('installs without tripping over the absent directory', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            ),
            completes,
          );

          expect(targetDirectory.existsSync(), isTrue);
        });
      });

      group('when the precache stamp cannot be written', () {
        setUp(() {
          createCheckout();
          // Occupying the stamp path with a directory makes createSync throw.
          Directory(
            p.join(targetDirectory.path, ShorebirdFlutter.precacheStampName),
          ).createSync(recursive: true);
        });

        test('fails loudly instead of exiting silently', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            ),
            throwsA(isA<CacheCorruptedException>()),
          );

          verify(
            () => progress.fail('Failed to precache Flutter 3.10.6'),
          ).called(1);
          verify(() => logger.err(any())).called(1);
        });
      });

      group('when the install is interrupted', () {
        setUp(() {
          when(
            () => git.checkout(
              directory: any(named: 'directory'),
              revision: any(named: 'revision'),
            ),
          ).thenThrow(Exception('interrupted'));
        });

        test('leaves no target directory and no staging directory', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            ),
            throwsException,
          );

          expect(targetDirectory.existsSync(), isFalse);
          expect(
            targetDirectory.parent.listSync().where(
              (e) => p.basename(e.path).startsWith(revision),
            ),
            isEmpty,
          );
        });
      });

      group('when another process publishes the revision first', () {
        setUp(() {
          when(
            () => git.checkout(
              directory: any(named: 'directory'),
              revision: any(named: 'revision'),
            ),
          ).thenAnswer((_) async {
            // Publishing makes this process's rename onto it fail.
            File(
              p.join(targetDirectory.path, 'already-here'),
            ).createSync(recursive: true);
          });
        });

        test('adopts the published checkout instead of failing', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            ),
            completes,
          );

          verifyNever(() => progress.fail(any()));
          expect(
            File(p.join(targetDirectory.path, 'already-here')).existsSync(),
            isTrue,
          );
          verify(
            () => process.run(
              'flutter',
              any(that: contains('precache')),
              workingDirectory: targetDirectory.path,
            ),
          ).called(1);
        });
      });

      test('throws exception if unable to clone', () async {
        final exception = Exception('oops');
        when(
          () => git.clone(
            url: any(named: 'url'),
            outputDirectory: any(named: 'outputDirectory'),
            args: any(named: 'args'),
          ),
        ).thenThrow(exception);

        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.installRevision(revision: revision),
          ),
          throwsA(exception),
        );

        verify(
          () => git.clone(
            url: ShorebirdFlutter.flutterGitUrl,
            outputDirectory: any(named: 'outputDirectory'),
            args: ['--filter=tree:0', '--no-checkout'],
          ),
        ).called(1);
        verifyNever(
          () => process.run(
            'flutter',
            any(that: contains('precache')),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        );
      });

      test('throws exception if unable to checkout revision', () async {
        final exception = Exception('oops');
        when(
          () => git.checkout(
            directory: any(named: 'directory'),
            revision: any(named: 'revision'),
          ),
        ).thenThrow(exception);

        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.installRevision(revision: revision),
          ),
          throwsA(exception),
        );
        verify(
          () => git.clone(
            url: ShorebirdFlutter.flutterGitUrl,
            outputDirectory: any(named: 'outputDirectory'),
            args: ['--filter=tree:0', '--no-checkout'],
          ),
        ).called(1);
        verify(
          () => git.checkout(
            directory: any(named: 'directory'),
            revision: revision,
          ),
        ).called(1);
        verify(
          () => logger.progress('Installing Flutter 3.10.6 (test-revis)'),
        ).called(1);
        verify(
          () => progress.fail('Failed to install Flutter 3.10.6 (test-revis)'),
        ).called(1);
      });

      group('when precache throws', () {
        setUp(() {
          when(
            () => process.run(
              'flutter',
              any(that: contains('precache')),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenThrow(Exception('oh no!'));
        });

        test(
          'throws CacheCorruptedException directing to shorebird cache clean',
          () async {
            await expectLater(
              runWithOverrides(
                () => shorebirdFlutter.installRevision(revision: revision),
              ),
              throwsA(
                isA<CacheCorruptedException>().having(
                  (e) => e.toString(),
                  'toString',
                  contains('shorebird cache clean'),
                ),
              ),
            );
            verify(
              () => progress.fail('Failed to precache Flutter 3.10.6'),
            ).called(1);
            // No stamp, so the next run retries precache.
            expect(precacheStamp.existsSync(), isFalse);
          },
        );
      });

      group('when precache exits with a non-zero code', () {
        setUp(() {
          when(() => precacheProcessResult.exitCode).thenReturn(1);
          when(() => precacheProcessResult.stderr).thenReturn('boom');
        });

        test(
          'throws CacheCorruptedException directing to shorebird cache clean',
          () async {
            await expectLater(
              runWithOverrides(
                () => shorebirdFlutter.installRevision(revision: revision),
              ),
              throwsA(
                isA<CacheCorruptedException>().having(
                  (e) => e.toString(),
                  'toString',
                  contains('shorebird cache clean'),
                ),
              ),
            );
            verify(
              () => progress.fail('Failed to precache Flutter 3.10.6'),
            ).called(1);
            // No stamp, so the next run retries precache.
            expect(precacheStamp.existsSync(), isFalse);
          },
        );
      });

      test('precaches the target revision, not the active revision', () async {
        ShorebirdEnv? envDuringPrecache;
        when(
          () => process.run(
            'flutter',
            any(that: contains('precache')),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async {
          envDuringPrecache = read(shorebirdEnvRef);
          return precacheProcessResult;
        });

        await runWithOverrides(
          () => shorebirdFlutter.installRevision(revision: revision),
        );

        // The vended `flutter` binary is resolved from the ambient revision,
        // so precache only warms [revision] if the scope says so.
        expect(envDuringPrecache, same(targetShorebirdEnv));
        expect(envDuringPrecache!.flutterRevision, revision);
        expect(shorebirdEnv.flutterRevision, isNot(revision));
      });

      group('when clone and checkout succeed', () {
        test('completes successfully', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            ),
            completes,
          );
          verify(
            () => process.run(
              'flutter',
              [
                'precache',
                ...runWithOverrides(() => shorebirdFlutter.precacheArgs),
              ],
              workingDirectory: p.join(flutterDirectory.parent.path, revision),
            ),
          ).called(1);
          verify(
            () => logger.progress('Installing Flutter 3.10.6 (test-revis)'),
          ).called(1);
          // Once for the installation and once for the precache.
          verify(progress.complete).called(2);
          expect(precacheStamp.existsSync(), isTrue);
        });
      });
    });

    group('isPorcelain', () {
      test('returns true when status is empty', () async {
        await expectLater(
          runWithOverrides(() => shorebirdFlutter.isUnmodified()),
          completion(isTrue),
        );
        verify(
          () => git.status(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            args: ['--untracked-files=no', '--porcelain'],
          ),
        ).called(1);
      });

      test('returns false when status is not empty', () async {
        when(
          () => git.status(
            directory: any(named: 'directory'),
            args: any(named: 'args'),
          ),
        ).thenAnswer((_) async => 'M some/file');
        await expectLater(
          runWithOverrides(() => shorebirdFlutter.isUnmodified()),
          completion(isFalse),
        );
        verify(
          () => git.status(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            args: ['--untracked-files=no', '--porcelain'],
          ),
        ).called(1);
      });

      test(
        'throws ProcessException when git command exits non-zero code',
        () async {
          const errorMessage = 'oh no!';
          when(
            () => git.status(
              directory: any(named: 'directory'),
              args: any(named: 'args'),
            ),
          ).thenThrow(
            ProcessException(
              'git',
              ['status'],
              errorMessage,
              ExitCode.software.code,
            ),
          );

          expect(
            runWithOverrides(() => shorebirdFlutter.isUnmodified()),
            throwsA(
              isA<ProcessException>().having(
                (e) => e.message,
                'message',
                errorMessage,
              ),
            ),
          );
        },
      );
    });

    group('formatVersion', () {
      test('returns the correct formatted value', () {
        expect(
          runWithOverrides(
            () => shorebirdFlutter.formatVersion(
              version: '3.10.6',
              revision: '771d07b2cf97cf107bae6eeedcf41bdc9db772fa',
            ),
          ),
          equals('3.10.6 (771d07b2cf)'),
        );
      });

      group('when version is null', () {
        test('returns unknown for the version', () {
          expect(
            runWithOverrides(
              () => shorebirdFlutter.formatVersion(
                version: null,
                revision: '771d07b2cf97cf107bae6eeedcf41bdc9db772fa',
              ),
            ),
            equals('unknown (771d07b2cf)'),
          );
        });
      });
    });
  });
}
