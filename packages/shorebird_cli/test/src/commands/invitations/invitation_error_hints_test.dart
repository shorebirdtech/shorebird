import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/commands/invitations/invitation_error_hints.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();

  group('invitationErrorHint', () {
    test('names the fix for each invitation error', () {
      expect(
        invitationErrorHint('invitation_email_mismatch'),
        contains('shorebird login'),
      );
      expect(
        invitationErrorHint('invitation_not_found'),
        contains('shorebird invitations list'),
      );
      expect(
        invitationErrorHint('invitation_gone'),
        allOf(contains('shorebird invitations list'), contains('new one')),
      );
      expect(
        invitationErrorHint('service_account_forbidden'),
        contains('SHOREBIRD_TOKEN'),
      );
    });

    test('has nothing to add for other errors', () {
      expect(invitationErrorHint('something_else'), isNull);
      expect(invitationErrorHint(null), isNull);
    });
  });

  group('withInvitationErrorHints', () {
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) =>
        runScoped(body, values: {loggerRef.overrideWith(() => logger)});

    setUp(() {
      logger = MockShorebirdLogger();
    });

    test('returns what the body returns', () async {
      final result = await runWithOverrides(
        () => withInvitationErrorHints(() async => 3),
      );
      expect(result, equals(3));
      verifyNever(() => logger.info(any()));
    });

    test('logs the hint and rethrows an API error exit', () async {
      final exit = ApiErrorExit(
        const CodePushException(
          message: 'Invitation not found',
          response: ErrorResponse(
            code: 'invitation_not_found',
            message: 'Invitation not found',
          ),
        ),
        ExitCode.software.code,
      );

      await expectLater(
        () => runWithOverrides(
          () => withInvitationErrorHints<int>(() async => throw exit),
        ),
        throwsA(same(exit)),
      );
      verify(
        () => logger.info(invitationErrorHint('invitation_not_found')),
      ).called(1);
    });

    test('rethrows an API error with no hint without logging', () async {
      final exit = ApiErrorExit(
        const CodePushException(
          message: 'boom',
          response: ErrorResponse(code: 'other', message: 'boom'),
        ),
        ExitCode.software.code,
      );

      await expectLater(
        () => runWithOverrides(
          () => withInvitationErrorHints<int>(() async => throw exit),
        ),
        throwsA(same(exit)),
      );
      verifyNever(() => logger.info(any()));
    });
  });
}
