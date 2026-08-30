import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/apps/apps.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  group(AppsTransferCommand, () {
    const appId = 'app-id';
    const displayName = 'Acme Mobile';
    const organizationId = 42;
    const organizationName = 'Acme Inc';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final app = AppMetadata(
      appId: appId,
      displayName: displayName,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final membership = OrganizationMembership(
      organization: Organization(
        id: organizationId,
        name: organizationName,
        organizationType: OrganizationType.team,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      role: Role.admin,
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late AppsTransferCommand command;

    R runWithOverrides<R>(
      R Function() body, {
      bool jsonMode = false,
    }) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    void verifyNeverTransferred() {
      verifyNever(
        () => codePushClientWrapper.transferApp(
          organizationId: any(named: 'organizationId'),
          appId: any(named: 'appId'),
        ),
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['app-id']).thenReturn(null);
      when(() => argResults['flavor']).thenReturn(null);
      when(() => argResults['org-id']).thenReturn('$organizationId');

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
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [membership]);
      when(
        () => codePushClientWrapper.transferApp(
          organizationId: any(named: 'organizationId'),
          appId: any(named: 'appId'),
        ),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(AppsTransferCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'transfer');
      expect(
        command.description,
        startsWith('Moves an app into a different organization.'),
      );
    });

    test('transfers the app', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.transferApp(
          organizationId: organizationId,
          appId: appId,
        ),
      ).called(1);
      verify(
        () => logger.success('Moved "$displayName" into "$organizationName".'),
      ).called(1);
    });

    group('when --org-id is not an integer', () {
      setUp(() => when(() => argResults['org-id']).thenReturn('not-a-number'));

      test('exits with usage and does not write', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverTransferred();
      });

      test('emits a usage_error envelope under --json', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.usage.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(
          (decoded['error'] as Map<String, dynamic>)['code'],
          'usage_error',
        );
      });
    });

    group('when the user is not a member of the target org', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
        ).thenAnswer((_) async => []);
      });

      test('exits with usage before writing', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverTransferred();
        verify(
          () => logger.err(
            'You are not a member of organization $organizationId.',
          ),
        ).called(1);
      });

      test('emits a usage_error envelope under --json', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.usage.code));
        verifyNeverTransferred();
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final error = decoded['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
        expect(error['hint'], 'Run: shorebird account orgs');
      });
    });

    group('--json', () {
      test('emits the destination organization', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
        expect(data['app_id'], appId);
        expect(data['display_name'], displayName);
        expect(data['to_organization_id'], organizationId);
        expect(data['to_organization_name'], organizationName);
      });
    });
  });
}
