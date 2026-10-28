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

  group(EnterprisesGetCommand, () {
    late EnterpriseHarness h;
    late EnterprisesGetCommand command;

    setUp(() {
      h = EnterpriseHarness();
      when(() => h.argResults['enterprise-id']).thenReturn(null);
      when(() => h.argResults.rest).thenReturn(['7']);
      when(
        () => h.codePushClientWrapper.getEnterprise(enterpriseId: 7),
      ).thenAnswer((_) async => EnterpriseFixtures.acmeEnterprise);
      command = h.run(EnterprisesGetCommand.new)..testArgResults = h.argResults;
    });

    test('prints the name and domains', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        allOf(contains('Acme'), endsWith('(id: 7)')),
        'Domains: acme.com, acme.dev',
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

    test('defaults to your only enterprise', () async {
      when(
        h.codePushClientWrapper.getEnterprises,
      ).thenAnswer((_) async => [EnterpriseFixtures.acme]);
      when(() => h.argResults.rest).thenReturn([]);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.codePushClientWrapper.getEnterprise(enterpriseId: 7),
      ).called(1);
    });

    test(
      'lists your enterprises when you have several and name none',
      () async {
        when(() => h.argResults.rest).thenReturn([]);
        expect(await h.run(command.run), ExitCode.usage.code);
        verify(() => h.logger.err('Pass an enterprise id.')).called(1);
        verify(
          () => h.logger.info(
            'Enterprise ids are integers, e.g. --enterprise-id 7. Your '
            'enterprises: Acme (id: 7), Beacon (id: 8).',
          ),
        ).called(1);
      },
    );

    test('rejects more than one id', () async {
      when(() => h.argResults.rest).thenReturn(['7', '8']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(h.codePushClientWrapper.getEnterprises);
    });

    test('rejects an id that is not a number', () async {
      when(() => h.argResults.rest).thenReturn(['acme']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err('"acme" is not a valid enterprise id.'),
      ).called(1);
    });

    test('names your enterprises for one you are not in', () async {
      when(() => h.argResults.rest).thenReturn(['99']);
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.usage.code);
      expect(json['error'], {
        'code': 'usage_error',
        'message': 'You are not a member of enterprise 99.',
        'hint': 'Your enterprises: Acme (id: 7), Beacon (id: 8).',
      });
    });

    test('says when you are in no enterprise', () async {
      when(h.codePushClientWrapper.getEnterprises).thenAnswer((_) async => []);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.info('You are not a member of any enterprise.'),
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
        'Failed to fetch enterprises.',
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
