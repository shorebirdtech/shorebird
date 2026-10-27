import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
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

  group(OrgsUpdateCommand, () {
    final membership = OrganizationMembership(
      organization: Organization(
        id: 42,
        name: 'Acme',
        organizationType: OrganizationType.team,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      role: Role.owner,
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late OrgsUpdateCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => json),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      shorebirdEnv = MockShorebirdEnv();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(OrgsUpdateCommand.new)
        ..testArgResults = argResults;

      when(() => argResults['name']).thenReturn('Acme Corp');
      when(() => argResults['org-id']).thenReturn('42');
      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [membership]);
      when(
        () => codePushClientWrapper.updateOrganization(
          organizationId: 42,
          name: 'Acme Corp',
        ),
      ).thenAnswer((_) async {});
    });

    test('is also spelled rename', () {
      expect(command.aliases, contains('rename'));
    });

    test('renames the organization', () async {
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => codePushClientWrapper.updateOrganization(
          organizationId: 42,
          name: 'Acme Corp',
        ),
      ).called(1);
      verify(() => logger.success('Renamed "Acme" to "Acme Corp".')).called(1);
    });

    test('takes the organization id as an argument', () async {
      when(() => argResults['org-id']).thenReturn(null);
      when(() => argResults.rest).thenReturn(['42']);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(null);
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [membership, membership]);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => codePushClientWrapper.updateOrganization(
          organizationId: 42,
          name: 'Acme Corp',
        ),
      ).called(1);
    });

    test('rejects a blank name before any request', () async {
      when(() => argResults['name']).thenReturn(' ');
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
      verify(
        () => logger.err('Organization name must not be blank.'),
      ).called(1);
      verifyNever(() => codePushClientWrapper.getOrganizationMemberships());
    });

    test('rejects the name it already has', () async {
      when(() => argResults['name']).thenReturn('Acme');
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
      verify(
        () => logger.err('Organization 42 is already named "Acme".'),
      ).called(1);
    });

    test('stops when the organization cannot be picked', () async {
      when(() => argResults['org-id']).thenReturn('99');
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
      verifyNever(
        () => codePushClientWrapper.updateOrganization(
          organizationId: any(named: 'organizationId'),
          name: any(named: 'name'),
        ),
      );
    });

    test('reports a failed request', () async {
      when(
        () => codePushClientWrapper.updateOrganization(
          organizationId: 42,
          name: 'Acme Corp',
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to rename organization 42.',
      );
    });

    test('--json emits the old and new names', () async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'id': 42,
        'from_name': 'Acme',
        'to_name': 'Acme Corp',
      });
    });
  });
}
