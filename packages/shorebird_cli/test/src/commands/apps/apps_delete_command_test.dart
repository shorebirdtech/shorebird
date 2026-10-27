import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/apps/apps.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AppsDeleteCommand, () {
    const appId = 'app-id';
    const organizationId = 42;
    const displayName = 'Acme Mobile';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final settingsUrl = Uri.parse(
      'https://console.shorebird.dev/orgs/$organizationId/apps/$appId/settings',
    );
    final app = AppMetadata(
      appId: appId,
      displayName: displayName,
      organizationId: organizationId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    late ArgResults argResults;
    late Browser browser;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late AppsDeleteCommand command;

    R runWithOverrides<R>(R Function() body, {bool jsonMode = false}) {
      return runScoped(
        body,
        values: {
          browserRef.overrideWith(() => browser),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    /// The only API request is reading the app: nothing is deleted.
    void verifyOnlyReadTheApp() {
      verify(() => codePushClientWrapper.getApp(appId: appId)).called(1);
      verifyNoMoreInteractions(codePushClientWrapper);
    }

    setUpAll(() => registerFallbackValue(Uri()));

    setUp(() {
      argResults = MockArgResults();
      browser = MockBrowser();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['app-id']).thenReturn(null);
      when(() => argResults['flavor']).thenReturn(null);
      when(() => browser.canOpen).thenReturn(true);
      when(() => browser.open(any())).thenAnswer((_) async => true);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
      when(
        () => shorebirdEnv.hostedEnvironment,
      ).thenReturn(productionEnvironment);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);

      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => app);

      command = runWithOverrides(AppsDeleteCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'delete');
      expect(
        command.description,
        startsWith("Opens the app's settings in the Shorebird console"),
      );
    });

    test('accepts the old --confirm-name and --yes, hidden', () {
      final parsed = command.argParser.parse(['--confirm-name', 'x', '-y']);
      expect(parsed['confirm-name'], 'x');
      expect(parsed['yes'], isTrue);
      expect(command.argParser.options['confirm-name']!.hide, isTrue);
      expect(command.argParser.options['yes']!.hide, isTrue);
    });

    test("opens the app's settings page in the console", () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => browser.open(settingsUrl)).called(1);
      verify(
        () => logger.info(
          any(
            that: allOf(
              contains('to delete app "$displayName" ($appId):'),
              contains('$settingsUrl'),
            ),
          ),
        ),
      ).called(1);
      verifyOnlyReadTheApp();
    });

    group('when not running interactively', () {
      setUp(() {
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
        when(() => argResults['confirm-name']).thenReturn(displayName);
      });

      test('fails with the console URL and deletes nothing', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.unavailable.code));
        verifyNever(() => browser.open(any()));
        verify(
          () => logger.err(
            'The Shorebird CLI does not delete app "$displayName" ($appId). '
            'A person finishes it in the Shorebird console: $settingsUrl',
          ),
        ).called(1);
        verifyOnlyReadTheApp();
      });

      test('emits a console_required envelope under --json', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.unavailable.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'console_required');
        expect(error['message'], contains('$settingsUrl'));
        verifyOnlyReadTheApp();
      });
    });

    test('emits a fetch_failed envelope when the fetch fails', () async {
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, jsonMode: true),
      );
      expect(exitCode, equals(ExitCode.software.code));
      verifyNever(() => browser.open(any()));
      expect(
        (json['error'] as Map<String, dynamic>)['code'],
        'fetch_failed',
      );
    });
  });
}
