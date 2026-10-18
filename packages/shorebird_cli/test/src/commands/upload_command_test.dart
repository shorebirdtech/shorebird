import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/upload_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/release_bundle.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(UploadCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0+1';
    const flutterRevision = 'deadbeef';
    const metadata = {'platform': 'android', 'generated_apks': false};
    final app = AppMetadata(
      appId: appId,
      displayName: 'My App',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    Release release({
      String revision = flutterRevision,
      Map<ReleasePlatform, ReleaseStatus> statuses = const {},
    }) => Release(
      id: 42,
      appId: appId,
      version: releaseVersion,
      flutterRevision: revision,
      flutterVersion: '3.35.0',
      displayName: releaseVersion,
      platformStatuses: statuses,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    late Directory tempDir;
    late File bundleFile;
    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late UploadCommand command;

    R runWithOverrides<R>(R Function() body, {bool jsonMode = false}) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    Future<void> writeBundle({String? flavor, bool withSupplement = false}) {
      File file(String name, String contents) =>
          File(p.join(tempDir.path, 'build', name))
            ..createSync(recursive: true)
            ..writeAsStringSync(contents);
      return ReleaseBundle(
        appId: appId,
        flavor: flavor,
        releaseType: ReleaseType.android,
        releaseVersion: releaseVersion,
        flutterRevision: flutterRevision,
        shorebirdVersion: '1.6.0',
        metadata: metadata,
        artifacts: [
          ReleaseArtifactUpload(
            file: file('libapp.so', 'arm64'),
            name: 'aarch64',
            arch: 'aarch64',
            platform: ReleasePlatform.android,
            canSideload: false,
          ),
          ReleaseArtifactUpload(
            file: file('app-release.aab', 'aab'),
            name: 'aab',
            arch: 'aab',
            platform: ReleasePlatform.android,
            canSideload: true,
          ),
        ],
        supplement: withSupplement
            ? ReleaseArtifactUpload(
                file: file('android_supplement.zip', 'supplement'),
                name: 'supplement',
                arch: 'android_supplement',
                platform: ReleasePlatform.android,
                canSideload: false,
              )
            : null,
      ).writeTo(bundleFile);
    }

    List<ReleaseArtifactUpload> verifyUploaded({String? message}) {
      return verify(
            () => codePushClientWrapper.uploadReleaseArtifacts(
              appId: appId,
              releaseId: 42,
              artifacts: captureAny(named: 'artifacts'),
              message: message == null
                  ? any(named: 'message')
                  : any(named: 'message', that: equals(message)),
            ),
          ).captured.single
          as List<ReleaseArtifactUpload>;
    }

    setUpAll(() {
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
      registerFallbackValue(<ReleaseArtifactUpload>[]);
      registerFallbackValue(release());
    });

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      addTearDown(() => tempDir.deleteSync(recursive: true));
      bundleFile = File(p.join(tempDir.path, 'release.zip'));
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults.rest).thenReturn([bundleFile.path]);
      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => app);
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => release());
      when(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
          metadata: any(named: 'metadata'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.uploadReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          artifacts: any(named: 'artifacts'),
          message: any(named: 'message'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(UploadCommand.new)
        ..testArgResults = argResults;
    });

    test('has a name, invocation and description', () {
      expect(command.name, equals('upload'));
      expect(command.invocation, equals('shorebird upload <bundle>'));
      expect(command.description, contains('--no-upload'));
    });

    test('requires exactly one bundle path', () async {
      when(() => argResults.rest).thenReturn([]);
      expect(
        await runWithOverrides(command.run),
        equals(ExitCode.usage.code),
      );
      verify(
        () => logger.err('Pass the path of one release bundle to upload.'),
      ).called(1);
    });

    test('exits when the user is not logged in', () async {
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(UserNotAuthorizedException());
      expect(
        await runWithOverrides(command.run),
        equals(ExitCode.noUser.code),
      );
      verifyNever(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      );
    });

    test('exits with a data error when the bundle cannot be read', () async {
      expect(await runWithOverrides(command.run), equals(ExitCode.data.code));
      verify(() => logger.err(any(that: contains('No file at')))).called(1);
      verifyNever(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      );
    });

    test('publishes a new release from the bundle', () async {
      await writeBundle(withSupplement: true);
      expect(
        await runWithOverrides(command.run),
        equals(ExitCode.success.code),
      );

      verify(
        () => codePushClientWrapper.createRelease(
          appId: appId,
          version: releaseVersion,
          flutterRevision: flutterRevision,
          platform: ReleasePlatform.android,
        ),
      ).called(1);
      verifyInOrder([
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: 42,
          platform: ReleasePlatform.android,
          status: ReleaseStatus.draft,
        ),
        () => codePushClientWrapper.uploadReleaseArtifacts(
          appId: appId,
          releaseId: 42,
          artifacts: any(named: 'artifacts'),
        ),
        () => codePushClientWrapper.uploadReleaseArtifacts(
          appId: appId,
          releaseId: 42,
          artifacts: any(named: 'artifacts'),
          message: 'Uploading supplement artifacts',
        ),
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: 42,
          platform: ReleasePlatform.android,
          status: ReleaseStatus.active,
          metadata: metadata,
        ),
      ]);
      verify(
        () => logger.success('\n✅ Published Release $releaseVersion!'),
      ).called(1);
      verify(
        () => logger.info(
          any(
            that: contains(
              'shorebird patch --platforms=android '
              '--release-version=$releaseVersion',
            ),
          ),
        ),
      ).called(1);
    });

    test('uploads the artifacts the bundle holds', () async {
      await writeBundle();
      await runWithOverrides(command.run);
      final uploaded = verifyUploaded();
      expect(
        [for (final a in uploaded) (a.arch, a.canSideload)],
        equals([('aarch64', false), ('aab', true)]),
      );
      verifyNever(
        () => codePushClientWrapper.uploadReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          artifacts: any(named: 'artifacts'),
          message: 'Uploading supplement artifacts',
        ),
      );
    });

    test('names the flavor in the summary and patch command', () async {
      await writeBundle(flavor: 'internal');
      await runWithOverrides(command.run);
      verify(
        () => logger.info(any(that: contains('🍧 Flavor:'))),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('--flavor=internal'))),
      ).called(1);
    });

    test('reuses a release that is not yet active', () async {
      await writeBundle();
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer(
        (_) async =>
            release(statuses: {ReleasePlatform.ios: ReleaseStatus.active}),
      );
      when(
        () => codePushClientWrapper.ensureReleaseIsNotActive(
          release: any(named: 'release'),
          platform: any(named: 'platform'),
        ),
      ).thenReturn(null);
      expect(
        await runWithOverrides(command.run),
        equals(ExitCode.success.code),
      );
      verifyNever(
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          platform: any(named: 'platform'),
        ),
      );
      verifyUploaded();
    });

    test(
      'refuses a release built with a different Flutter revision',
      () async {
        await writeBundle();
        when(
          () => codePushClientWrapper.maybeGetRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenAnswer((_) async => release(revision: 'cafef00d'));
        when(
          () => codePushClientWrapper.ensureReleaseIsNotActive(
            release: any(named: 'release'),
            platform: any(named: 'platform'),
          ),
        ).thenReturn(null);
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.software.code),
        );
        verify(
          () => logger.err(any(that: contains('already exists, built with'))),
        ).called(1);
        verifyNever(
          () => codePushClientWrapper.uploadReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            artifacts: any(named: 'artifacts'),
            message: any(named: 'message'),
          ),
        );
      },
    );

    test('emits the published release with --json', () async {
      await writeBundle();
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, jsonMode: true),
      );
      expect(exitCode, equals(ExitCode.success.code));
      expect(json['data'], {
        'app_id': appId,
        'platform': 'android',
        'release_version': releaseVersion,
        'release_id': 42,
      });
      verifyNever(() => logger.success(any()));
    });

    test('deletes what it extracted', () async {
      await writeBundle();
      final systemTemp = createSystemTemp();
      await runWithSystemTemp(systemTemp, () => runWithOverrides(command.run));
      expect(systemTemp.listSync(), isEmpty);
    });
  });
}
