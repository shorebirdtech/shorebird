import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_session.dart';
import 'package:shorebird_cli/src/build_history.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'mocks.dart';

void main() {
  useTempWorkingDirectory();

  group(BuildHistory, () {
    final startedAt = DateTime.utc(2026, 11, 10, 17);
    const appId = 'app-id';

    late ArtifactBuilder artifactBuilder;
    late BuildTraceSession buildTraceSession;
    late CodePushClient codePushClient;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late BuildHistory buildHistory;
    late DateTime now;

    R runWithOverrides<R>(R Function() body) => runScoped(
      () => withClock(Clock(() => now), body),
      values: {
        artifactBuilderRef.overrideWith(() => artifactBuilder),
        buildTraceSessionRef.overrideWith(() => buildTraceSession),
        codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
        loggerRef.overrideWith(() => logger),
      },
    );

    BuildRun startRun() => runWithOverrides(
      () => buildHistory.start(
        command: BuildRunCommand.patch,
        platform: ReleasePlatform.ios,
        dryRun: false,
      ),
    )..appId = appId;

    CreateBuildRunRequest sentRequest() =>
        verify(
              () => codePushClient.createBuildRun(
                appId: appId,
                request: captureAny(named: 'request'),
              ),
            ).captured.single
            as CreateBuildRunRequest;

    Future<void> recordRun(
      BuildRun run,
      Future<void> Function() body, {
      Future<Json> Function()? metadata,
    }) async {
      try {
        await runWithOverrides(
          () => buildHistory.record(
            run,
            () async {
              now = startedAt.add(const Duration(seconds: 3));
              await body();
            },
            metadata: metadata ?? () async => {'from': 'callback'},
          ),
        );
      } on Object {
        // Each test checks what was thrown where it matters.
      }
    }

    setUpAll(() {
      registerFallbackValue(FakeCreateBuildRunRequest());
    });

    setUp(() {
      now = startedAt;
      artifactBuilder = MockArtifactBuilder();
      buildTraceSession = BuildTraceSession(commandStartedAt: startedAt);
      codePushClient = MockCodePushClient();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      buildHistory = BuildHistory(runId: 'run-id');

      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(
        () => codePushClient.createBuildRun(
          appId: any(named: 'appId'),
          request: any(named: 'request'),
        ),
      ).thenAnswer((_) async {});
    });

    test('gives each instance its own run id', () {
      expect(BuildHistory().runId, isNot(BuildHistory().runId));
    });

    group('start', () {
      test('clears the build trace a previous platform left', () {
        buildTraceSession
          ..traceFile = File('trace.json')
          ..platform = 'android';

        final run = startRun();

        expect(buildTraceSession.traceFile, isNull);
        expect(buildTraceSession.platform, isNull);
        expect(buildTraceSession.summary, isNull);
        expect(run.runId, equals('run-id'));
        expect(run.startedAt, equals(startedAt));
      });
    });

    group('record', () {
      test('sends a run that returns as succeeded', () async {
        final run = startRun()
          ..releaseId = 1
          ..patchId = 2
          ..metadata = {'from': 'run'};

        await recordRun(run, () async {});

        final request = sentRequest();
        expect(request.runId, equals('run-id'));
        expect(request.command, equals(BuildRunCommand.patch));
        expect(request.platform, equals(ReleasePlatform.ios));
        expect(request.outcome, equals(BuildRunOutcome.succeeded));
        expect(request.reason, isNull);
        expect(request.releaseId, equals(1));
        expect(request.patchId, equals(2));
        expect(request.startedAt, equals(startedAt));
        expect(request.durationMs, equals(3000));
        expect(request.dryRun, isFalse);
        expect(request.metadata, equals({'from': 'run'}));
      });

      test('returns what the run returns', () async {
        final result = await runWithOverrides(
          () => buildHistory.record(
            startRun(),
            () async => 42,
            metadata: () async => {},
          ),
        );
        expect(result, equals(42));
      });

      test('sends a dry run that exits with success as succeeded', () async {
        final run = startRun();

        await expectLater(
          runWithOverrides(
            () => buildHistory.record(
              run,
              () async => throw ProcessExit(ExitCode.success.code),
              metadata: () async => {'from': 'callback'},
            ),
          ),
          throwsA(isA<ProcessExit>()),
        );

        final request = sentRequest();
        expect(request.outcome, equals(BuildRunOutcome.succeeded));
        expect(request.metadata, equals({'from': 'callback'}));
      });

      test('writes the build trace summary of a failed run', () async {
        await recordRun(
          startRun(),
          () async => throw ProcessExit(ExitCode.software.code),
        );

        verify(() => artifactBuilder.writeBuildTraceSummary()).called(1);
      });

      test('sends the reason the command set', () async {
        final run = startRun()..failWith(BuildRunFailureReason.linkPercentage);

        await recordRun(
          run,
          () async => throw ProcessExit(ExitCode.software.code),
        );

        final request = sentRequest();
        expect(request.outcome, equals(BuildRunOutcome.failed));
        expect(request.reason, equals(BuildRunFailureReason.linkPercentage));
      });

      final exits = <String, (Exception, BuildRunFailureReason)>{
        'an API error': (
          ApiErrorExit(
            const CodePushException(message: 'nope'),
            ExitCode.software.code,
          ),
          BuildRunFailureReason.serverRejected,
        ),
        'a declined prompt': (
          PromptDeclinedExit(),
          BuildRunFailureReason.canceled,
        ),
        'another exit': (
          ProcessExit(ExitCode.software.code),
          BuildRunFailureReason.other,
        ),
        'a usage error': (
          UsageException('bad', 'usage'),
          BuildRunFailureReason.other,
        ),
      };
      for (final MapEntry(key: name, value: (error, reason)) in exits.entries) {
        test('classifies $name with no reason set as '
            '${reason.value}', () async {
          await expectLater(
            runWithOverrides(
              () => buildHistory.record(
                startRun(),
                () async => throw error,
                metadata: () async => {},
              ),
            ),
            throwsA(same(error)),
          );

          final request = sentRequest();
          expect(request.outcome, equals(BuildRunOutcome.failed));
          expect(request.reason, equals(reason));
        });
      }

      test('sends nothing for a crash', () async {
        await expectLater(
          runWithOverrides(
            () => buildHistory.record(
              startRun(),
              () async => throw StateError('boom'),
              metadata: () async => {},
            ),
          ),
          throwsStateError,
        );

        verifyNever(
          () => codePushClient.createBuildRun(
            appId: any(named: 'appId'),
            request: any(named: 'request'),
          ),
        );
      });

      test('sends nothing for a run with no app', () async {
        final run = runWithOverrides(
          () => buildHistory.start(
            command: BuildRunCommand.release,
            platform: ReleasePlatform.android,
            dryRun: false,
          ),
        );

        await recordRun(
          run,
          () async => throw ProcessExit(ExitCode.software.code),
        );

        verifyNever(
          () => codePushClient.createBuildRun(
            appId: any(named: 'appId'),
            request: any(named: 'request'),
          ),
        );
      });

      test('sends no metadata when describing the run fails', () async {
        await recordRun(
          startRun(),
          () async => throw ProcessExit(ExitCode.software.code),
          metadata: () async => throw Exception('no xcode'),
        );

        expect(sentRequest().metadata, isNull);
        verify(
          () => logger.detail(
            any(that: contains('Could not describe this run')),
          ),
        ).called(1);
      });

      test('keeps the result of a run it could not send', () async {
        when(
          () => codePushClient.createBuildRun(
            appId: any(named: 'appId'),
            request: any(named: 'request'),
          ),
        ).thenThrow(const CodePushException(message: 'offline'));

        final result = await runWithOverrides(
          () => buildHistory.record(
            startRun(),
            () async => 'published',
            metadata: () async => {},
          ),
        );

        expect(result, equals('published'));
        verify(
          () => logger.detail(any(that: contains('Could not record this run'))),
        ).called(1);
      });

      test('rethrows the run failure when the send fails too', () async {
        final exit = ProcessExit(ExitCode.software.code);
        when(
          () => codePushClient.createBuildRun(
            appId: any(named: 'appId'),
            request: any(named: 'request'),
          ),
        ).thenThrow(const CodePushException(message: 'offline'));

        await expectLater(
          runWithOverrides(
            () => buildHistory.record(
              startRun(),
              () async => throw exit,
              metadata: () async => {},
            ),
          ),
          throwsA(same(exit)),
        );
      });
    });

    group('buildFlags', () {
      final parser = ArgParser()
        ..addMultiOption('dart-define', splitCommas: false)
        ..addMultiOption('dart-define-from-file', splitCommas: false);

      String hash(String value) =>
          sha256.convert(utf8.encode(value)).toString();

      test('holds the define hashes and their count, never values', () {
        final flags = buildHistory.buildFlags(
          parser.parse(['--dart-define=API_KEY=secret', '--dart-define=B=2']),
        )!;

        expect(flags.dartDefineCount, equals(2));
        expect(
          flags.dartDefines,
          equals({'API_KEY': hash('secret'), 'B': hash('2')}),
        );
        expect(flags.target, isNull);
        expect(json.encode(flags.toJson()), isNot(contains('secret')));
      });

      test('hashes the target', () {
        final flags = buildHistory.buildFlags(
          parser.parse([]),
          target: 'lib/main_prod.dart',
        )!;

        expect(flags.dartDefineCount, equals(0));
        expect(flags.target, equals(hash('lib/main_prod.dart')));
      });

      test('is null when a define file cannot be read', () {
        expect(
          runWithOverrides(
            () => buildHistory.buildFlags(
              parser.parse(['--dart-define-from-file=missing.json']),
            ),
          ),
          isNull,
        );
      });
    });
  });

  group('blameFailureOn', () {
    BuildRun newRun() => BuildRun(
      runId: 'run-id',
      command: BuildRunCommand.release,
      platform: ReleasePlatform.android,
      dryRun: false,
      startedAt: DateTime.utc(2026),
    );

    test('blames a failed exit on the reason', () async {
      final run = newRun();
      await expectLater(
        blameFailureOn(
          run,
          BuildRunFailureReason.buildFailed,
          () async => throw ProcessExit(ExitCode.software.code),
        ),
        throwsA(isA<ProcessExit>()),
      );
      expect(run.reason, equals(BuildRunFailureReason.buildFailed));
    });

    test('keeps the first reason', () async {
      final run = newRun()..failWith(BuildRunFailureReason.linkPercentage);
      await expectLater(
        blameFailureOn(
          run,
          BuildRunFailureReason.buildFailed,
          () async => throw ProcessExit(ExitCode.software.code),
        ),
        throwsA(isA<ProcessExit>()),
      );
      expect(run.reason, equals(BuildRunFailureReason.linkPercentage));
    });

    for (final exit in [
      ApiErrorExit(
        const CodePushException(message: 'nope'),
        ExitCode.software.code,
      ),
      PromptDeclinedExit(),
      ProcessExit(ExitCode.success.code),
    ]) {
      test('leaves ${exit.runtimeType} '
          '(exit ${exit.exitCode}) to be classified', () async {
        final run = newRun();
        await expectLater(
          blameFailureOn(
            run,
            BuildRunFailureReason.buildFailed,
            () async => throw exit,
          ),
          throwsA(same(exit)),
        );
        expect(run.reason, isNull);
      });
    }

    test('returns what the body returns', () async {
      expect(
        await blameFailureOn(
          null,
          BuildRunFailureReason.uploadFailed,
          () async => 1,
        ),
        equals(1),
      );
    });
  });
}
