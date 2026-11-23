import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache_pruning.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(FlutterPathCommand, () {
    const pinnedRevision = 'pinned1234567890';
    const requestedRevision = 'requested1234567890';
    late Directory tempDirectory;
    late String pinnedPath;
    late String requestedPath;

    late ArgResults argResults;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late FlutterPathCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          isJsonModeRef.overrideWith(() => json),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    Future<({int exitCode, List<String> stdout})> runCommand() async {
      final captured = <String>[];
      final exitCode = await captureStdout(
        () => runWithOverrides(command.run),
        captured: captured,
      );
      return (exitCode: exitCode, stdout: captured);
    }

    Future<({int exitCode, Map<String, dynamic> error})> runJsonError() async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      return (exitCode: exitCode, error: json['error'] as Map<String, dynamic>);
    }

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync();
      addTearDown(() => tempDirectory.deleteSync(recursive: true));
      pinnedPath = p.join(tempDirectory.path, pinnedRevision);
      requestedPath = p.join(tempDirectory.path, requestedRevision);
      argResults = MockArgResults();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      command = FlutterPathCommand()..testArgResults = argResults;

      when(() => argResults['flutter-version']).thenReturn(null);
      when(() => argResults.rest).thenReturn([]);
      when(() => logger.level).thenReturn(Level.info);
      when(() => shorebirdEnv.flutterRevision).thenReturn(pinnedRevision);
      when(
        () => shorebirdEnv.logsDirectory,
      ).thenReturn(Directory(p.join(tempDirectory.path, 'logs')));
      when(
        () => shorebirdFlutter.isInstalled(revision: any(named: 'revision')),
      ).thenReturn(true);
      when(
        () => shorebirdFlutter.installDirectory(revision: pinnedRevision),
      ).thenReturn(Directory(pinnedPath));
      when(
        () => shorebirdFlutter.installDirectory(revision: requestedRevision),
      ).thenReturn(Directory(requestedPath));
      when(
        () => shorebirdFlutter.resolveFlutterRevision(any()),
      ).thenAnswer((_) async => requestedRevision);
    });

    test('has correct name', () {
      expect(command.name, equals('path'));
      expect(command.reservesStdout, isTrue);
    });

    group('when --flutter-version is omitted', () {
      test('prints only the pinned Flutter directory', () async {
        final result = await runCommand();
        expect(result.exitCode, equals(ExitCode.success.code));
        expect(result.stdout, equals([pinnedPath]));
        verifyNever(() => shorebirdFlutter.resolveFlutterRevision(any()));
        verifyNever(() => shorebirdFlutter.fetchRemoteRefs());
      });

      test('records the install as used so pruning keeps it', () async {
        await runCommand();
        expect(
          File(p.join(pinnedPath, lastUsedStampName)).existsSync(),
          isTrue,
        );
      });

      test('fails and suggests precache when not installed', () async {
        when(
          () => shorebirdFlutter.isInstalled(revision: pinnedRevision),
        ).thenReturn(false);
        final result = await runCommand();
        expect(result.exitCode, equals(ExitCode.unavailable.code));
        expect(result.stdout, isEmpty);
      });
    });

    test('treats latest as the pinned Flutter', () async {
      when(() => argResults['flutter-version']).thenReturn('latest');
      final result = await runCommand();
      expect(result.stdout, equals([pinnedPath]));
    });

    group('when --flutter-version names a version', () {
      setUp(() {
        when(() => argResults['flutter-version']).thenReturn('3.38.5');
      });

      test('prints the resolved revision directory', () async {
        final result = await runCommand();
        expect(result.exitCode, equals(ExitCode.success.code));
        expect(result.stdout, equals([requestedPath]));
        verify(
          () => shorebirdFlutter.resolveFlutterRevision('3.38.5'),
        ).called(1);
        verifyNever(() => shorebirdFlutter.fetchRemoteRefs());
      });

      test('fails when the revision is not installed', () async {
        when(
          () => shorebirdFlutter.isInstalled(revision: requestedRevision),
        ).thenReturn(false);
        final result = await runCommand();
        expect(result.exitCode, equals(ExitCode.unavailable.code));
        expect(result.stdout, isEmpty);
        final (:exitCode, :error) = await runJsonError();
        expect(exitCode, equals(ExitCode.unavailable.code));
        expect(error, {
          'code': 'precondition_failed',
          'message': 'Flutter 3.38.5 is not installed.',
          'hint': 'Run: shorebird flutter precache --flutter-version 3.38.5',
        });
      });

      test('fails when the version is unknown locally', () async {
        when(
          () => shorebirdFlutter.resolveFlutterRevision(any()),
        ).thenAnswer((_) async => null);
        final (:exitCode, :error) = await runJsonError();
        expect(exitCode, equals(ExitCode.unavailable.code));
        expect(error['message'], equals('Flutter 3.38.5 is not installed.'));
        expect(error['hint'], contains('shorebird flutter versions list'));
      });

      test('fails when resolving throws', () async {
        when(
          () => shorebirdFlutter.resolveFlutterRevision(any()),
        ).thenThrow(const ProcessException('git', ['for-each-ref']));
        final (:exitCode, :error) = await runJsonError();
        expect(exitCode, equals(ExitCode.unavailable.code));
        expect(error['message'], equals('Flutter 3.38.5 is not installed.'));
      });
    });

    test('refuses a version passed as an argument', () async {
      when(() => argResults.rest).thenReturn(['3.38.5']);
      final (:exitCode, :error) = await runJsonError();
      expect(exitCode, equals(ExitCode.usage.code));
      expect(error, {
        'code': 'usage_error',
        'message': 'shorebird flutter path takes no arguments.',
        'hint':
            'Pass a version with --flutter-version, e.g. '
            '--flutter-version=3.38.5',
      });
      verifyNever(
        () => shorebirdFlutter.isInstalled(revision: any(named: 'revision')),
      );
    });

    for (final alias in ['system', 'fvm']) {
      test('refuses --flutter-version=$alias', () async {
        when(() => argResults['flutter-version']).thenReturn(alias);
        final (:exitCode, :error) = await runJsonError();
        expect(exitCode, equals(ExitCode.usage.code));
        expect(
          error['message'],
          equals(
            '--flutter-version=$alias is not supported by '
            'shorebird flutter path.',
          ),
        );
        verifyNever(() => shorebirdFlutter.resolveFlutterRevision(any()));
      });
    }

    group('in JSON mode', () {
      test('emits the path and revision', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect(
          json['data'],
          equals({'path': pinnedPath, 'revision': pinnedRevision}),
        );
      });

      test('emits an error when not installed', () async {
        when(
          () => shorebirdFlutter.isInstalled(revision: any(named: 'revision')),
        ).thenReturn(false);
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, equals(ExitCode.unavailable.code));
        expect(json['error'], {
          'code': 'precondition_failed',
          'message': "Shorebird's Flutter is not installed.",
          'hint': 'Run: shorebird flutter precache',
        });
      });
    });
  });
}
