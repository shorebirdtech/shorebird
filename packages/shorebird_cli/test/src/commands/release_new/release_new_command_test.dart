import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/android_release_pipeline.dart';
import 'package:shorebird_cli/src/commands/release_new/release_new_command.dart';
import 'package:shorebird_cli/src/commands/release_new/release_pipeline_old.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(ReleaseNewCommand, () {
    const appId = 'app-id';
    const appDisplayName = 'app-display-name';
    final appMetadata = AppMetadata(
      appId: appId,
      displayName: appDisplayName,
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ReleasePipelineOld pipeline;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;

    late ReleaseNewCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      pipeline = MockReleasePipeline();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();

      when(() => argResults['flavor']).thenReturn(null);
      when(() => argResults.wasParsed('flavor')).thenReturn(false);
      when(() => argResults['platform']).thenReturn(['android']);
      when(() => argResults['target']).thenReturn(null);
      when(() => argResults.wasParsed('target')).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);

      when(() => codePushClientWrapper.getApp(appId: any(named: 'appId')))
          .thenAnswer((_) async => appMetadata);

      when(() => pipeline.validateArgs()).thenAnswer((_) async => {});
      when(() => pipeline.validatePreconditions()).thenAnswer((_) async => {});

      when(
        () => shorebirdEnv.copyWith(
          flutterRevisionOverride: any(named: 'flutterRevisionOverride'),
        ),
      ).thenAnswer((invocation) {
        when(() => shorebirdEnv.flutterRevision).thenReturn(
          invocation.namedArguments[#flutterRevisionOverride] as String,
        );
        return shorebirdEnv;
      });

      command = runWithOverrides(ReleaseNewCommand.new)
        ..testArgResults = argResults;
    });

    group('pipelines', () {
      test('transforms platforms arg into pipelines', () async {
        when(() => argResults['platform']).thenReturn(['android']);
        final pipelines = runWithOverrides(() => command.pipelines);
        expect(pipelines.length, equals(1));
        expect(pipelines.first, isA<AndroidReleasePipline>());
      });
    });

    group('createRelease', () {
      test('invokes pipeline functions in proper order', () async {
        await runWithOverrides(() => command.createRelease(pipeline));

        verifyInOrder([
          () async => pipeline.validatePreconditions(),
          () async => pipeline.validateArgs(),
          () async => pipeline.buildReleaseArtifacts(),
        ]);
      });
    });
  });
}
