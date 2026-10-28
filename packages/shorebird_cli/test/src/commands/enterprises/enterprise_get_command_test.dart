import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'enterprise_fixtures.dart';
import 'enterprise_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(EnterpriseGetCommand, () {
    late EnterpriseHarness h;
    late EnterpriseGetCommand command;

    setUp(() {
      h = EnterpriseHarness();
      when(
        () => h.codePushClientWrapper.getEnterprise(enterpriseId: 7),
      ).thenAnswer((_) async => EnterpriseFixtures.acmeEnterprise);
      command = h.run(EnterpriseGetCommand.new)..testArgResults = h.argResults;
    });

    test('prints the name and domains', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        allOf(contains('Acme'), endsWith('(id: 7)')),
        'Domains: acme.com, acme.dev',
        'Your role: admin',
      ]);
    });

    test('says when it has no domains', () async {
      when(
        () => h.codePushClientWrapper.getEnterprise(enterpriseId: 7),
      ).thenAnswer(
        (_) async => Enterprise.fromJson(const {
          'id': 7,
          'name': 'Acme',
          'domains': <String>[],
        }),
      );
      expect(await h.run(command.run), ExitCode.success.code);
      verify(() => h.logger.info('Domains: none')).called(1);
    });

    test('--json includes your role', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'id': 7,
        'name': 'Acme',
        'role': 'admin',
        'domains': ['acme.com', 'acme.dev'],
      });
    });

    test('runs from real arguments', () async {
      command.testArgResults = command.argParser.parse([]);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.codePushClientWrapper.getEnterprise(enterpriseId: 7),
      ).called(1);
    });

    test('takes no arguments', () async {
      when(() => h.argResults.rest).thenReturn(['7']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(h.codePushClientWrapper.getEnterprises);
    });

    test('says when you are in no enterprise', () async {
      when(h.codePushClientWrapper.getEnterprises).thenAnswer((_) async => []);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err("You aren't a member of an enterprise."),
      ).called(1);
    });

    test('reports a failed fetch of your enterprises', () async {
      when(
        h.codePushClientWrapper.getEnterprises,
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch your enterprise.',
      );
    });

    test('reports a failed fetch of the enterprise', () async {
      when(
        () => h.codePushClientWrapper.getEnterprise(enterpriseId: 7),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch enterprise 7.',
      );
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
