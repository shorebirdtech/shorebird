import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/apps/apps.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(AppsListCommand, () {
    final app = AppMetadata(
      appId: '01H000000000000000000ABCDE',
      displayName: 'Acme Mobile',
      latestReleaseVersion: '1.2.3',
      latestPatchNumber: 4,
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 16),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late AppsListCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => false),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(AppsListCommand.new)
        ..testArgResults = argResults;

      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getApps(),
      ).thenAnswer((_) async => [app]);
    });

    test('name and description are correct', () {
      expect(command.name, 'list');
      expect(
        command.description,
        startsWith('Lists the apps you have access to.'),
      );
      expect(command.description, contains('shorebird apps list --json'));
    });

    // The listing itself is AccountAppsCommand's, which has its own coverage.
    // This asserts the subclass still reaches it.
    test('lists the apps', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => codePushClientWrapper.getApps()).called(1);
      verify(
        () => logger.info(any(that: contains(app.appId))),
      ).called(1);
    });
  });
}
