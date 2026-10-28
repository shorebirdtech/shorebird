import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'enterprise_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(EnterprisesListCommand, () {
    late EnterpriseHarness h;
    late EnterprisesListCommand command;

    setUp(() {
      h = EnterpriseHarness();
      command = h.run(EnterprisesListCommand.new)
        ..testArgResults = h.argResults;
    });

    test('prints one line per enterprise', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        allOf(startsWith('7  '), contains('Acme'), endsWith('admin')),
        allOf(startsWith('8  '), contains('Beacon'), endsWith('member')),
      ]);
    });

    test('says when you are in none', () async {
      when(h.codePushClientWrapper.getEnterprises).thenAnswer((_) async => []);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.info('You are not a member of any enterprise.'),
      ).called(1);
    });

    test('--json lists ids, names and roles', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'enterprises': [
          {'id': 7, 'name': 'Acme', 'role': 'admin'},
          {'id': 8, 'name': 'Beacon', 'role': 'member'},
        ],
      });
    });

    test('needs a signed-in user', () async {
      final exception = UserNotAuthorizedException();
      when(
        () => h.shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).thenThrow(exception);
      expect(await h.run(command.run), exception.exitCode.code);
    });
  });
}
