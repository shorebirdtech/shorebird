import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();

  group(OrgsCreateCommand, () {
    final organization = Organization(
      id: 42,
      name: 'Acme Corp',
      organizationType: OrganizationType.team,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late OrgsCreateCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => json),
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
      command = runWithOverrides(OrgsCreateCommand.new)
        ..testArgResults = argResults;

      when(() => argResults['name']).thenReturn(null);
      when(() => argResults.rest).thenReturn(['Acme Corp']);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.createOrganization(name: 'Acme Corp'),
      ).thenAnswer((_) async => organization);
    });

    test('creates the organization named by the argument', () async {
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => logger.success('Created organization "Acme Corp" (id: 42).'),
      ).called(1);
    });

    test('takes the name from --name, trimmed', () async {
      when(() => argResults['name']).thenReturn(' Acme Corp ');
      when(() => argResults.rest).thenReturn([]);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => codePushClientWrapper.createOrganization(name: 'Acme Corp'),
      ).called(1);
    });

    test('asks for a name when given none', () async {
      when(() => argResults.rest).thenReturn([]);
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
      verify(
        () => logger.err(
          'Name the organization: shorebird orgs create "Acme Corp".',
        ),
      ).called(1);
    });

    test('rejects a name split across arguments', () async {
      when(() => argResults.rest).thenReturn(['Acme', 'Corp']);
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
      verify(
        () => logger.err(
          'Pass the organization name once, quoted if it has spaces: '
          'shorebird orgs create "Acme Corp".',
        ),
      ).called(1);
      verifyNever(
        () =>
            codePushClientWrapper.createOrganization(name: any(named: 'name')),
      );
    });

    test('rejects a name passed both ways', () async {
      when(() => argResults['name']).thenReturn('Acme Corp');
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
    });

    test('rejects a blank name', () async {
      when(() => argResults.rest).thenReturn(['  ']);
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
      verify(
        () => logger.err('Organization name must not be blank.'),
      ).called(1);
    });

    test('requires the user to be signed in', () async {
      final exception = UserNotAuthorizedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).thenThrow(exception);
      expect(await runWithOverrides(command.run), exception.exitCode.code);
    });

    test('reports a failed request', () async {
      when(
        () => codePushClientWrapper.createOrganization(name: 'Acme Corp'),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to create organization "Acme Corp".',
      );
    });

    test('--json emits the new organization', () async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'id': 42,
        'name': 'Acme Corp',
        'type': 'team',
        'role': 'owner',
      });
    });
  });
}
