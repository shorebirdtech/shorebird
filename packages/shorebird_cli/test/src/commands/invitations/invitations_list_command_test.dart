import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/invitations/invitations.dart';
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
  group(InvitationsListCommand, () {
    final orgInvitation = ReceivedInvitation(
      id: '11111111-1111-4111-8111-111111111111',
      organizationId: 1,
      targetName: 'Acme Corp',
      inviterEmail: 'admin@acme.com',
      role: Role.developer,
      createdAt: DateTime.utc(2026, 10, 16, 12),
      expiresAt: DateTime.utc(2026, 10, 30, 12),
    );
    final appInvitation = ReceivedInvitation(
      id: '22222222-2222-4222-8222-222222222222',
      appId: 'app-id',
      targetName: 'Acme Mobile',
      inviterEmail: 'owner@acme.com',
      role: Role.admin,
      createdAt: DateTime.utc(2026, 10, 15, 12),
      expiresAt: DateTime.utc(2026, 10, 29, 12),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late InvitationsListCommand command;

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
      command = runWithOverrides(InvitationsListCommand.new)
        ..testArgResults = argResults;

      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getReceivedInvitations(),
      ).thenAnswer((_) async => [orgInvitation, appInvitation]);
    });

    test('has a description that names the accept command', () {
      expect(
        command.description,
        allOf(
          startsWith('List the pending invitations sent to you.'),
          contains('shorebird invitations accept <id>'),
        ),
      );
    });

    test('returns the precondition failure exit code', () async {
      final exception = UserNotAuthorizedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);

      final result = await runWithOverrides(command.run);

      expect(result, equals(exception.exitCode.code));
      verifyNever(() => codePushClientWrapper.getReceivedInvitations());
    });

    test('prints one line per invitation', () async {
      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      final lines = verify(
        () => logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, hasLength(2));
      expect(
        lines[0],
        allOf(
          contains(orgInvitation.id),
          contains('Acme Corp'),
          contains('organization'),
          contains('developer'),
          contains('admin@acme.com'),
          contains('2026-10-16'),
        ),
      );
      expect(
        lines[1],
        allOf(contains('Acme Mobile'), contains('app'), contains('admin')),
      );
    });

    test('says so when there are no invitations', () async {
      when(
        () => codePushClientWrapper.getReceivedInvitations(),
      ).thenAnswer((_) async => []);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('No pending invitations.')).called(1);
    });

    group('--json', () {
      test('emits every invitation with flat fields', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );

        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], 'success');
        final invitations =
            ((json['data'] as Map<String, dynamic>)['invitations'] as List)
                .cast<Map<String, dynamic>>();
        expect(invitations, hasLength(2));
        expect(
          invitations[0],
          equals({
            'id': orgInvitation.id,
            'kind': 'organization',
            'organization_id': 1,
            'app_id': null,
            'name': 'Acme Corp',
            'role': 'developer',
            'inviter_email': 'admin@acme.com',
            'created_at': '2026-10-16T12:00:00.000Z',
            'expires_at': '2026-10-30T12:00:00.000Z',
          }),
        );
        expect(invitations[1]['kind'], 'app');
        expect(invitations[1]['app_id'], 'app-id');
      });

      test('emits an empty list when there are no invitations', () async {
        when(
          () => codePushClientWrapper.getReceivedInvitations(),
        ).thenAnswer((_) async => []);

        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );

        expect(exitCode, equals(ExitCode.success.code));
        expect((json['data'] as Map<String, dynamic>)['invitations'], isEmpty);
      });

      test('emits a JSON error when the fetch fails', () async {
        when(
          () => codePushClientWrapper.getReceivedInvitations(),
        ).thenThrow(ProcessExit(ExitCode.software.code));

        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );

        expect(exitCode, equals(ExitCode.software.code));
        expect(json['status'], 'error');
      });
    });
  });
}
