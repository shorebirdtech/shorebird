import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:clock/clock.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/audit_log/audit_log.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';
import 'audit_log_test_helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(AuditLogExportCommand, () {
    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AuditLogExportCommand command;

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

    /// Runs the export as a person would, returning its exit code (null if
    /// it exited by throwing [ProcessExit]) and what it wrote to stdout and
    /// to stderr. Inside the export, the CLI's own logger writes to stderr.
    Future<({int? exitCode, List<String> stdout, List<String> stderr})>
    runExport() async {
      final out = <String>[];
      final err = <String>[];
      final realStdout = stdout;
      final realStderr = stderr;
      int? exitCode;
      try {
        exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          stdout: () => CapturingStdout(baseStdOut: realStdout, captured: out),
          stderr: () => CapturingStdout(baseStdOut: realStderr, captured: err),
        );
      } on ProcessExit {
        exitCode = null;
      }
      return (exitCode: exitCode, stdout: out, stderr: err);
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
      when(() => logger.level).thenReturn(Level.info);
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(AuditLogExportCommand.new)
        ..testArgResults = argResults;

      when(() => argResults.rest).thenReturn([]);
      for (final option in [
        'app-id',
        'actor',
        'event',
        'start',
        'end',
        'cursor',
      ]) {
        stubOption(option, null);
      }
      stubOption('org-id', '42');
      when(() => argResults['order']).thenReturn('desc');
      when(() => argResults.wasParsed('order')).thenReturn(false);
      when(() => argResults['format']).thenReturn('json');
      when(() => argResults.wasParsed('format')).thenReturn(false);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [auditLogMembership]);
      stubAuditLogPages(codePushClientWrapper, {
        null: GetOrganizationAuditLogsResponse(
          data: [auditLogEntry()],
          nextCursor: 'p2',
        ),
        'p2': GetOrganizationAuditLogsResponse(data: [auditLogEntry(uid: '2')]),
      });
    });

    test('keeps stdout for the entries', () {
      expect(command.reservesStdout, isTrue);
    });

    test('writes every page as one JSON array', () async {
      final (:exitCode, :stdout, :stderr) = await runExport();
      expect(exitCode, ExitCode.success.code);
      expect(stdout, hasLength(1));
      expect(entryIds(jsonDecode(stdout.single) as List), ['1', '2']);
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
      final (:exitCode, :stdout, :stderr) = await runExport();
      expect(exitCode, ExitCode.success.code);
      expect(entryIds(stdout.map(jsonDecode).toList()), ['1', '2']);
    });

    group('oldest first', () {
      setUp(() {
        stubOption('start', '2026-10-01');
        when(() => argResults['order']).thenReturn('asc');
        when(() => argResults.wasParsed('order')).thenReturn(true);
        stubAuditLogPages(codePushClientWrapper, {
          null: GetOrganizationAuditLogsResponse(
            data: [auditLogEntry()],
            nextCursor: 'p2',
          ),
          'p2': const GetOrganizationAuditLogsResponse(
            data: [],
            nextCursor: 'p2',
          ),
        });
      });

      test('stops at an empty page and gives the command to resume, '
          'with the filters', () async {
        final (:exitCode, :stdout, :stderr) = await runExport();
        expect(exitCode, ExitCode.success.code);
        expect(entryIds(jsonDecode(stdout.single) as List), ['1']);
        expect(
          stderr,
          contains(
            'To export newer entries later: shorebird audit-log export '
            '--org-id 42 --start 2026-10-01 --order asc --cursor p2',
          ),
        );
      });

      test('resumes from the time a duration meant', () async {
        stubOption('start', '7d');
        final (:exitCode, :stdout, :stderr) = await withClock(
          Clock.fixed(DateTime.utc(2026, 10, 28, 12, 30, 15)),
          runExport,
        );
        expect(exitCode, ExitCode.success.code);
        expect(
          stderr,
          contains(
            'To export newer entries later: shorebird audit-log export '
            '--org-id 42 --start 2026-10-21T12:30:15Z --order asc --cursor p2',
          ),
        );
      });

      test('--json gives the cursor to resume from', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, ExitCode.success.code);
        final data = json['data'] as Map<String, dynamic>;
        expect(entryIds(data['entries'] as List), ['1']);
        expect(data['next_cursor'], 'p2');
      });
    });

    group('when a later page fails', () {
      setUp(() {
        stubAuditLogPages(
          codePushClientWrapper,
          {
            null: GetOrganizationAuditLogsResponse(
              data: [auditLogEntry()],
              nextCursor: 'p2',
            ),
          },
          failAt: (cursor: 'p2', error: ProcessExit(ExitCode.software.code)),
        );
      });

      test('a jsonl export says how to continue after what it wrote', () async {
        when(() => argResults['format']).thenReturn('jsonl');
        when(() => argResults.wasParsed('format')).thenReturn(true);
        final (:exitCode, :stdout, :stderr) = await runExport();
        expect(exitCode, isNull);
        expect(entryIds(stdout.map(jsonDecode).toList()), ['1']);
        expect(
          stderr,
          contains(
            'The 1 entries before the failure were written. To continue '
            'after them: shorebird audit-log export --org-id 42 '
            '--format jsonl --cursor p2',
          ),
        );
      });

      test('a JSON array export writes nothing and gives no cursor', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, ExitCode.software.code);
        expect((json['error'] as Map)['hint'], isNull);
      });
    });

    test('rejects --format with --json', () async {
      when(() => argResults.wasParsed('format')).thenReturn(true);
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.usage.code);
      expect(
        (json['error'] as Map)['message'],
        '--json puts the entries in its envelope; drop --format, or drop '
        '--json to write json.',
      );
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
}
