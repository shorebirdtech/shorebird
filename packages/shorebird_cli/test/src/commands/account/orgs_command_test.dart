import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/orgs_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  group(OrgsCommand, () {
    final teamMembership = OrganizationMembership(
      organization: Organization(
        id: 1,
        name: 'Acme Corp',
        organizationType: OrganizationType.team,
        createdAt: DateTime(2026, 1, 15),
        updatedAt: DateTime(2026, 1, 16),
      ),
      role: Role.admin,
    );
    final personalMembership = OrganizationMembership(
      organization: Organization(
        id: 2,
        name: 'user@example.com',
        organizationType: OrganizationType.personal,
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 11),
      ),
      role: Role.owner,
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late OrgsCommand command;

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
      command = runWithOverrides(OrgsCommand.new)..testArgResults = argResults;

      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [teamMembership, personalMembership]);
    });

    test('has correct description', () {
      expect(
        command.description,
        startsWith('List the organizations you belong to.'),
      );
    });

    group('when validation fails', () {
      final exception = UserNotAuthorizedException();

      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          ),
        ).thenThrow(exception);
      });

      test('returns the precondition failure exit code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(exception.exitCode.code));
      });
    });

    test('requires user to be authenticated', () async {
      await runWithOverrides(command.run);
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    group('human-readable output', () {
      test('prints one line per organization', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final lines = verify(
          () => logger.info(captureAny()),
        ).captured.cast<String>();
        expect(lines, hasLength(2));
        expect(lines[0], allOf(contains('Acme Corp'), contains('admin')));
        expect(
          lines[1],
          allOf(contains('user@example.com'), contains('owner')),
        );
      });

      group('when there are no organizations', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getOrganizationMemberships(),
          ).thenAnswer((_) async => []);
        });

        test('prints an empty-state message', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(() => logger.info('No organizations found.')).called(1);
        });
      });
    });

    group('when API fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('in human-readable mode, rethrows ProcessExit', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ProcessExit>()),
        );
      });

      test('in --json mode, emits JSON error envelope', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runScoped(
            command.run,
            values: {
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              isJsonModeRef.overrideWith(() => true),
              loggerRef.overrideWith(() => logger),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
          captured: captured,
        );
        expect(result, equals(ExitCode.software.code));
        expect(captured, hasLength(1));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'error');
      });
    });

    group('--json', () {
      R runJsonMode<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            isJsonModeRef.overrideWith(() => true),
            loggerRef.overrideWith(() => logger),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        );
      }

      test('emits JSON success with flat organization fields', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runJsonMode(command.run),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        expect(captured, hasLength(1));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'success');
        final data = decoded['data'] as Map<String, dynamic>;
        final orgs = data['organizations'] as List<dynamic>;
        expect(orgs, hasLength(2));
        final firstOrg = orgs.first as Map<String, dynamic>;
        expect(firstOrg['id'], 1);
        expect(firstOrg['name'], 'Acme Corp');
        expect(firstOrg['type'], 'team');
        expect(firstOrg['role'], 'admin');
      });

      test('does not leak timestamps or protocol-internal fields', () async {
        final captured = <String>[];
        await captureStdout(
          () => runJsonMode(command.run),
          captured: captured,
        );
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final orgs =
            ((decoded['data'] as Map<String, dynamic>)['organizations']
                    as List<dynamic>)
                .cast<Map<String, dynamic>>();
        for (final org in orgs) {
          expect(org.containsKey('created_at'), isFalse);
          expect(org.containsKey('updated_at'), isFalse);
          expect(org.containsKey('organization_type'), isFalse);
          expect(org.containsKey('organization'), isFalse);
        }
      });

      test('emits empty array when there are no organizations', () async {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
        ).thenAnswer((_) async => []);
        final captured = <String>[];
        final result = await captureStdout(
          () => runJsonMode(command.run),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
        expect(data['organizations'], isEmpty);
      });
    });
  });
}
