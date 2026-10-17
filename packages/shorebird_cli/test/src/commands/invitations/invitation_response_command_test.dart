import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/invitations/invitations.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();

  const invitationId = '11111111-1111-4111-8111-111111111111';

  late ArgResults argResults;
  late CodePushClientWrapper codePushClientWrapper;
  late ShorebirdValidator shorebirdValidator;
  late ShorebirdLogger logger;

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

    when(() => argResults.rest).thenReturn([invitationId]);
    when(
      () => shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => codePushClientWrapper.acceptInvitation(
        invitationId: any(named: 'invitationId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => codePushClientWrapper.declineInvitation(
        invitationId: any(named: 'invitationId'),
      ),
    ).thenAnswer((_) async {});
  });

  for (final (
        create,
        name,
        pastTense,
        respond,
      )
      in <
        (
          InvitationResponseCommand Function(),
          String,
          String,
          Future<void> Function({required String invitationId}) Function(),
        )
      >[
        (
          InvitationsAcceptCommand.new,
          'accept',
          'accepted',
          () => codePushClientWrapper.acceptInvitation,
        ),
        (
          InvitationsDeclineCommand.new,
          'decline',
          'declined',
          () => codePushClientWrapper.declineInvitation,
        ),
      ]) {
    group('invitations $name', () {
      late InvitationResponseCommand command;

      setUp(() {
        command = runWithOverrides(create)..testArgResults = argResults;
      });

      test('has the correct name and invocation', () {
        expect(command.name, equals(name));
        expect(command.invocation, equals('shorebird invitations $name <id>'));
        expect(
          command.description,
          contains('shorebird invitations list'),
        );
      });

      test('requires exactly one invitation id', () async {
        when(() => argResults.rest).thenReturn([]);
        command.testRunner = usageRunner();

        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('Expected exactly one invitation <id>, got 0.'),
            ),
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
      });

      test('answers the invitation and says so', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(() => respond()(invitationId: invitationId)).called(1);
        final verb = '${pastTense[0].toUpperCase()}${pastTense.substring(1)}';
        verify(
          () => logger.success('$verb invitation $invitationId.'),
        ).called(1);
      });

      test('emits JSON success in --json mode', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );

        expect(exitCode, equals(ExitCode.success.code));
        expect(
          json['data'],
          equals({'invitation_id': invitationId, 'status': pastTense}),
        );
      });

      test('emits a JSON error when the request fails', () async {
        when(
          () => respond()(invitationId: any(named: 'invitationId')),
        ).thenThrow(ProcessExit(ExitCode.software.code));

        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );

        expect(exitCode, equals(ExitCode.software.code));
        expect(json['status'], 'error');
      });
    });
  }
}
