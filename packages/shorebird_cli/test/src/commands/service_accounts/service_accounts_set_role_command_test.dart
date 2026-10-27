import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'service_account_fixtures.dart';

void main() {
  useTempWorkingDirectory();

  group(ServiceAccountsSetRoleCommand, () {
    late ServiceAccountTestContext context;
    final asViewer = ServiceAccount(
      id: releaseBot.id,
      organizationId: releaseBot.organizationId,
      name: releaseBot.name,
      label: releaseBot.label,
      role: ServiceAccountRole.viewer,
      createdAt: releaseBot.createdAt,
      createdByUserId: releaseBot.createdByUserId,
      createdByEmail: releaseBot.createdByEmail,
      lastAuthAt: releaseBot.lastAuthAt,
    );

    setUp(() {
      context = ServiceAccountTestContext();
      when(
        () => context.wrapper.updateServiceAccount(
          organizationId: 42,
          serviceAccountId: 383,
          role: ServiceAccountRole.viewer,
        ),
      ).thenAnswer((_) async => asViewer);
    });

    test('changes the role', () async {
      expect(
        await context.runCommand(ServiceAccountsSetRoleCommand(), [
          'release-bot',
          '--role',
          'viewer',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      verify(
        () => context.logger.success(
          'Changed the role of "release-bot" from developer to viewer.',
        ),
      ).called(1);
    });

    test('offers only service account roles', () {
      expect(
        () => ServiceAccountsSetRoleCommand().argParser.parse([
          'release-bot',
          '--role',
          'admin',
        ]),
        throwsFormatException,
      );
    });

    test('--json emits the account and its old role', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountsSetRoleCommand(), [
          'release-bot',
          '--role',
          'viewer',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, ExitCode.success.code);
      final data = json['data'] as Map<String, dynamic>;
      expect(data['role'], 'viewer');
      expect(data['from_role'], 'developer');
    });
  });
}
