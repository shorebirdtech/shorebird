import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/audit_log_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();

  group(AuditLogCommand, () {
    final membership = OrganizationMembership(
      organization: Organization(
        id: 42,
        name: 'Acme Corp',
        organizationType: OrganizationType.team,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      role: Role.owner,
    );

    AuditLogEvent entry({
      String uid = '1',
      Map<String, dynamic> user = const {
        'uid': '12',
        'email_addr': 'alice@acme.com',
        'type_id': 1,
        'type': 'User',
      },
    }) => AuditLogEvent.fromJson({
      'class_uid': 6003,
      'category_uid': 6,
      'activity_id': 3,
      'type_uid': 600303,
      // 2026-10-20 14:03:22 UTC.
      'time': DateTime.utc(2026, 10, 20, 14, 3, 22).millisecondsSinceEpoch,
      'severity_id': 1,
      'status_id': 1,
      'metadata': {
        'version': '1.9.0',
        'product': const {'name': 'Shorebird', 'vendor_name': 'Shorebird'},
        'uid': uid,
        'tenant_uid': '42',
        'log_name': 'audit',
      },
      'api': const {'operation': 'organization.rename'},
      'actor': {'user': user},
      'src_endpoint': const {'ip': '203.0.113.7'},
      'resources': const [
        {'type': 'organization', 'uid': '42'},
      ],
      'unmapped': const <String, dynamic>{},
    });

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AuditLogCommand command;

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

    void stubPages(Map<String?, GetOrganizationAuditLogsResponse> pages) {
      when(
        () => codePushClientWrapper.getOrganizationAuditLogs(
          organizationId: any(named: 'organizationId'),
          perPage: any(named: 'perPage'),
          cursor: any(named: 'cursor'),
          order: any(named: 'order'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          appId: any(named: 'appId'),
          actorId: any(named: 'actorId'),
          operation: any(named: 'operation'),
        ),
      ).thenAnswer(
        (invocation) async =>
            pages[invocation.namedArguments[#cursor] as String?]!,
      );
    }

    setUpAll(() {
      registerFallbackValue(AuditLogOrder.desc);
    });

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      when(() => logger.level).thenReturn(Level.info);
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(AuditLogCommand.new)
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
        when(() => argResults[option]).thenReturn(null);
      }
      when(() => argResults['org-id']).thenReturn('42');
      when(() => argResults['order']).thenReturn('desc');
      when(() => argResults['format']).thenReturn('json');
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [membership]);
      stubPages({
        null: GetOrganizationAuditLogsResponse(data: [entry()]),
      });
    });

    test('accepts the spellings agents guess', () {
      expect(command.aliases, ['audit-logs', 'audit']);
    });

    group('one page', () {
      test('prints one line per entry', () async {
        expect(await runWithOverrides(command.run), ExitCode.success.code);
        verify(
          () => logger.info(
            '2026-10-20 14:03:22Z  ${lightCyan.wrap('organization.rename')}  '
            'alice@acme.com (id: 12)  organization:42',
          ),
        ).called(1);
      });

      test('also runs as audit-log list', () async {
        when(() => argResults.rest).thenReturn(['list']);
        expect(await runWithOverrides(command.run), ExitCode.success.code);
      });

      test('names Shorebird staff without an id', () async {
        stubPages({
          null: GetOrganizationAuditLogsResponse(
            data: [
              entry(
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
        stubPages({null: const GetOrganizationAuditLogsResponse(data: [])});
        await runWithOverrides(command.run);
        verify(() => logger.info('No audit log entries.')).called(1);
      });

      test('says how to get the next page', () async {
        stubPages({
          null: GetOrganizationAuditLogsResponse(
            data: [entry()],
            nextCursor: 'abc',
          ),
        });
        await runWithOverrides(command.run);
        verify(
          () => logger.info(
            'Next page: pass --cursor abc with the same filters.',
          ),
        ).called(1);
      });

      test('sends the filters', () async {
        when(() => argResults['app-id']).thenReturn('app-1');
        when(() => argResults['actor']).thenReturn('12');
        when(() => argResults['event']).thenReturn('organization.rename');
        when(() => argResults['start']).thenReturn('2026-10-01');
        when(() => argResults['end']).thenReturn('2026-10-02');
        when(() => argResults['order']).thenReturn('asc');
        when(() => argResults['limit']).thenReturn('5');
        when(() => argResults['cursor']).thenReturn('c');
        stubPages({
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

      test('--json emits the entries as OCSF events', () async {
        stubPages({
          null: GetOrganizationAuditLogsResponse(
            data: [entry()],
            nextCursor: 'abc',
          ),
        });
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, ExitCode.success.code);
        expect(json['data'], {
          'organization_id': 42,
          'entries': [jsonDecode(jsonEncode(entry().toJson()))],
          'next_cursor': 'abc',
        });
      });
    });

    group('rejects bad input before any request', () {
      Future<void> expectUsageError(String message) async {
        expect(await runWithOverrides(command.run), ExitCode.usage.code);
        verify(() => logger.err(message)).called(1);
        verifyNever(() => codePushClientWrapper.getOrganizationMemberships());
      }

      test('an unknown argument', () async {
        when(() => argResults.rest).thenReturn(['download']);
        await expectUsageError(
          'Unexpected argument "download". Run `shorebird audit-log` for one '
          'page or `shorebird audit-log export` for every page.',
        );
      });

      test('an actor that is not an id', () async {
        when(() => argResults['actor']).thenReturn('alice@acme.com');
        await expectUsageError(
          '"alice@acme.com" is not an actor id. Pass the id each entry shows '
          'beside its actor, e.g. --actor 12.',
        );
      });

      test('a limit out of range', () async {
        when(() => argResults['limit']).thenReturn('500');
        await expectUsageError(
          '--limit must be a number from 1 to 100 (got "500").',
        );
      });

      test('a limit on export', () async {
        when(() => argResults.rest).thenReturn(['export']);
        when(() => argResults['limit']).thenReturn('5');
        await expectUsageError('export writes every page; drop --limit.');
      });

      test('a time that does not parse', () async {
        when(() => argResults['start']).thenReturn('last week');
        await expectUsageError(
          'Pass --start as a date (2026-10-01) or an ISO 8601 time '
          '(2026-10-01T09:00:00Z), not "last week".',
        );
      });
    });

    group('when the plan lacks the audit log', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getOrganizationAuditLogs(
            organizationId: any(named: 'organizationId'),
            perPage: any(named: 'perPage'),
            cursor: any(named: 'cursor'),
            order: any(named: 'order'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            appId: any(named: 'appId'),
            actorId: any(named: 'actorId'),
            operation: any(named: 'operation'),
          ),
        ).thenThrow(
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

      test('says which plan has it', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ApiErrorExit>()),
        );
        verify(
          () => logger.info(
            'The audit log is part of the Enterprise plan. See '
            'https://shorebird.dev/pricing.',
          ),
        ).called(1);
      });

      test('--json reports the API code', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, ExitCode.software.code);
        expect(
          (json['error'] as Map)['api_code'],
          'shorebird_plan_insufficient_tier',
        );
      });
    });

    test('reports a failed request', () async {
      when(
        () => codePushClientWrapper.getOrganizationAuditLogs(
          organizationId: any(named: 'organizationId'),
          perPage: any(named: 'perPage'),
          cursor: any(named: 'cursor'),
          order: any(named: 'order'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          appId: any(named: 'appId'),
          actorId: any(named: 'actorId'),
          operation: any(named: 'operation'),
        ),
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

    group('export', () {
      setUp(() {
        when(() => argResults.rest).thenReturn(['export']);
        stubPages({
          null: GetOrganizationAuditLogsResponse(
            data: [entry()],
            nextCursor: 'p2',
          ),
          'p2': GetOrganizationAuditLogsResponse(data: [entry(uid: '2')]),
        });
      });

      List<String> entryIds(List<dynamic> entries) => [
        for (final e in entries.cast<Map<String, dynamic>>())
          (e['metadata'] as Map)['uid'] as String,
      ];

      test('writes every page as one JSON array', () async {
        final captured = <String>[];
        final exitCode = await captureStdout(
          () => runWithOverrides(command.run),
          captured: captured,
        );
        expect(exitCode, ExitCode.success.code);
        expect(captured, hasLength(1));
        expect(entryIds(jsonDecode(captured.single) as List), ['1', '2']);
        verify(
          () => codePushClientWrapper.getOrganizationAuditLogs(
            organizationId: 42,
            perPage: 100,
            cursor: 'p2',
            order: AuditLogOrder.desc,
          ),
        ).called(1);
      });

      test('writes one entry per line with --format jsonl', () async {
        when(() => argResults['format']).thenReturn('jsonl');
        final captured = <String>[];
        await captureStdout(
          () => runWithOverrides(command.run),
          captured: captured,
        );
        expect(entryIds(captured.map(jsonDecode).toList()), ['1', '2']);
      });

      test('oldest first, stops at an empty page', () async {
        when(() => argResults['order']).thenReturn('asc');
        stubPages({
          null: GetOrganizationAuditLogsResponse(
            data: [entry()],
            nextCursor: 'p2',
          ),
          'p2': const GetOrganizationAuditLogsResponse(
            data: [],
            nextCursor: 'p2',
          ),
        });
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, ExitCode.success.code);
        final data = json['data'] as Map<String, dynamic>;
        expect(entryIds(data['entries'] as List), ['1']);
        // So a poller can resume where this run stopped.
        expect(data['next_cursor'], 'p2');
      });

      test('--json emits every entry in the envelope', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, ExitCode.success.code);
        final data = json['data'] as Map<String, dynamic>;
        expect(entryIds(data['entries'] as List), ['1', '2']);
        expect(data['next_cursor'], isNull);
      });
    });
  });
}
