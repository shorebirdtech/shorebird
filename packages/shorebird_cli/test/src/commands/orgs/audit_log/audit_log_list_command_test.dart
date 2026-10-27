import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/audit_log/audit_log.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../../helpers.dart';
import '../../../mocks.dart';
import 'audit_log_test_helpers.dart';

void main() {
  useTempWorkingDirectory();

  // AuditLogListCommand also covers the filters it shares with export.
  group(AuditLogListCommand, () {
    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AuditLogListCommand command;

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

    void stubOption(String name, String? value) {
      when(() => argResults[name]).thenReturn(value);
      when(() => argResults.wasParsed(name)).thenReturn(value != null);
    }

    setUpAll(() {
      registerFallbackValue(AuditLogOrder.desc);
    });

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(AuditLogListCommand.new)
        ..testArgResults = argResults;

      when(() => argResults.rest).thenReturn([]);
      for (final option in [
        'app-id',
        'actor',
        'event',
        'start',
        'end',
        'limit',
        'cursor',
      ]) {
        stubOption(option, null);
      }
      stubOption('org-id', '42');
      when(() => argResults['order']).thenReturn('desc');
      when(() => argResults.wasParsed('order')).thenReturn(false);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [auditLogMembership]);
      stubAuditLogPages(codePushClientWrapper, {
        null: GetOrganizationAuditLogsResponse(data: [auditLogEntry()]),
      });
    });

    test('prints one line per entry', () async {
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => logger.info(
          '2026-10-20 14:03:22Z  ${lightCyan.wrap('organization.rename')}  '
          'alice@acme.com (id: 12)  organization:42',
        ),
      ).called(1);
    });

    test('takes the org id as an argument', () async {
      stubOption('org-id', null);
      when(() => argResults.rest).thenReturn(['42']);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => codePushClientWrapper.getOrganizationAuditLogs(
          organizationId: 42,
          order: AuditLogOrder.desc,
        ),
      ).called(1);
    });

    test('names Shorebird staff without an id', () async {
      stubAuditLogPages(codePushClientWrapper, {
        null: GetOrganizationAuditLogsResponse(
          data: [
            auditLogEntry(
              user: const {
                'name': 'Shorebird staff',
                'type_id': 99,
                'type': 'shorebird_staff',
              },
            ),
          ],
        ),
      });
      await runWithOverrides(command.run);
      final line =
          verify(() => logger.info(captureAny())).captured.single as String;
      expect(line, contains('  Shorebird staff  '));
    });

    test('says when there are no entries', () async {
      stubAuditLogPages(codePushClientWrapper, {
        null: const GetOrganizationAuditLogsResponse(data: []),
      });
      await runWithOverrides(command.run);
      verify(() => logger.info('No audit log entries.')).called(1);
    });

    test('gives the command for the next page, with the filters', () async {
      stubOption('event', 'organization.rename');
      stubOption('start', '2026-10-01');
      stubOption('limit', '5');
      stubAuditLogPages(codePushClientWrapper, {
        null: GetOrganizationAuditLogsResponse(
          data: [auditLogEntry()],
          nextCursor: 'abc',
        ),
      });
      await runWithOverrides(command.run);
      verify(
        () => logger.info(
          'Next page: shorebird orgs audit-log list --org-id 42 '
          '--event organization.rename --start 2026-10-01 --limit 5 '
          '--cursor abc',
        ),
      ).called(1);
    });

    test('sends the filters', () async {
      stubOption('app-id', 'app-1');
      stubOption('actor', '12');
      stubOption('event', 'organization.rename');
      stubOption('start', '2026-10-01');
      stubOption('end', '2026-10-02');
      when(() => argResults['order']).thenReturn('asc');
      stubOption('limit', '5');
      stubOption('cursor', 'c');
      stubAuditLogPages(codePushClientWrapper, {
        'c': const GetOrganizationAuditLogsResponse(data: []),
      });
      await runWithOverrides(command.run);
      verify(
        () => codePushClientWrapper.getOrganizationAuditLogs(
          organizationId: 42,
          perPage: 5,
          cursor: 'c',
          order: AuditLogOrder.asc,
          startDate: DateTime.utc(2026, 10),
          // A date means through the end of that day.
          endDate: DateTime.utc(2026, 10, 2, 23, 59, 59, 999),
          appId: 'app-1',
          actorId: 12,
          operation: 'organization.rename',
        ),
      ).called(1);
    });

    test('takes a time with its zone', () async {
      stubOption('start', '2026-10-01T09:00:00+02:00');
      await runWithOverrides(command.run);
      verify(
        () => codePushClientWrapper.getOrganizationAuditLogs(
          organizationId: 42,
          order: AuditLogOrder.desc,
          startDate: DateTime.utc(2026, 10, 1, 7),
        ),
      ).called(1);
    });

    test('--json emits the entries as OCSF events', () async {
      stubAuditLogPages(codePushClientWrapper, {
        null: GetOrganizationAuditLogsResponse(
          data: [auditLogEntry()],
          nextCursor: 'abc',
        ),
      });
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'organization_id': 42,
        'entries': [jsonDecode(jsonEncode(auditLogEntry().toJson()))],
        'next_cursor': 'abc',
      });
    });

    group('rejects bad input before any request', () {
      Future<void> expectUsageError(String message) async {
        expect(await runWithOverrides(command.run), ExitCode.usage.code);
        verify(() => logger.err(message)).called(1);
        verifyNever(() => codePushClientWrapper.getOrganizationMemberships());
      }

      test('an actor that is not an id', () async {
        stubOption('actor', 'alice@acme.com');
        await expectUsageError(
          '"alice@acme.com" is not an actor id. Pass the id each entry shows '
          'beside its actor, e.g. --actor 12.',
        );
      });

      test('a limit out of range', () async {
        stubOption('limit', '500');
        await expectUsageError(
          '--limit must be a number from 1 to 100 (got "500").',
        );
      });

      for (final (option, value) in [
        ('start', 'last week'),
        // Read as local midnight, not a date, by DateTime.parse.
        ('end', '20261001'),
        // No zone: local time, which the help doesn't promise.
        ('start', '2026-10-01T09:00:00'),
        // Rolled over into March by DateTime.parse.
        ('start', '2026-02-30'),
      ]) {
        test('--$option $value', () async {
          stubOption(option, value);
          await expectUsageError(
            'Pass --$option as a date (2026-10-01) or a time with its zone '
            '(2026-10-01T09:00:00Z), not "$value".',
          );
        });
      }

      test('a start after the end', () async {
        stubOption('start', '2026-10-02');
        stubOption('end', '2026-10-01');
        await expectUsageError(
          '--start (2026-10-02) is after --end (2026-10-01), so no entry '
          'could match.',
        );
      });
    });

    group('when the plan lacks the audit log', () {
      setUp(() {
        when(() => anyAuditLogFetch(codePushClientWrapper)).thenThrow(
          ApiErrorExit(
            const CodePushException(
              message: 'The account requires an upgraded plan.',
              statusCode: 403,
              response: ErrorResponse(
                code: 'shorebird_plan_insufficient_tier',
                message: 'The account requires an upgraded plan.',
              ),
            ),
            ExitCode.software.code,
          ),
        );
      });

      const hint =
          "Your plan doesn't include the audit log. See "
          'https://shorebird.dev/pricing.';

      test('says so', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ApiErrorExit>()),
        );
        verify(() => logger.info(hint)).called(1);
      });

      test('--json says so too, with the API code', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, ExitCode.software.code);
        final error = json['error'] as Map;
        expect(error['api_code'], 'shorebird_plan_insufficient_tier');
        expect(error['hint'], hint);
      });
    });

    test('reports a failed request', () async {
      when(
        () => anyAuditLogFetch(codePushClientWrapper),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch the audit log of organization 42.',
      );
    });
  });
}
