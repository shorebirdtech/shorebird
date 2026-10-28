import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

import '../../mocks.dart';

/// Shared fixtures and mocks for the `shorebird members` command tests.
class MembersHarness {
  MembersHarness() {
    when(() => argResults['org-id']).thenReturn('42');
    when(() => argResults.rest).thenReturn([]);
    when(
      () => shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
      ),
    ).thenAnswer((_) async {});
    when(shorebirdEnv.getShorebirdYaml).thenReturn(null);
    when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
    when(
      codePushClientWrapper.getOrganizationMemberships,
    ).thenAnswer((_) async => [membership]);
    when(
      () => codePushClientWrapper.getOrganizationUsers(organizationId: 42),
    ).thenAnswer((_) async => [owner, bob]);
    when(
      () => codePushClientWrapper.maybeGetOrganizationInvitations(
        organizationId: 42,
      ),
    ).thenAnswer((_) async => [carolInvite]);
  }

  static final membership = OrganizationMembership(
    organization: Organization(
      id: 42,
      name: 'Acme Corp',
      organizationType: OrganizationType.team,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
    role: Role.admin,
  );
  static const owner = OrganizationUser(
    user: PublicUser(id: 1, email: 'alice@acme.com'),
    role: Role.owner,
  );
  static const bob = OrganizationUser(
    user: PublicUser(id: 7, email: 'bob@acme.com', displayName: 'Bob'),
    role: Role.developer,
  );
  static final carolInvite = InvitationSummary(
    id: 'inv-1',
    email: 'carol@acme.com',
    role: Role.viewer,
    createdAt: DateTime.utc(2026, 10, 27),
    expiresAt: DateTime.utc(2026, 11, 10),
  );

  final ArgResults argResults = MockArgResults();
  final CodePushClientWrapper codePushClientWrapper =
      MockCodePushClientWrapper();
  final ShorebirdEnv shorebirdEnv = MockShorebirdEnv();
  final ShorebirdLogger logger = MockShorebirdLogger();
  final ShorebirdValidator shorebirdValidator = MockShorebirdValidator();

  R run<R>(R Function() body, {bool json = false}) {
    return runScoped(
      body,
      values: {
        codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
        isJsonModeRef.overrideWith(() => json),
        loggerRef.overrideWith(() => logger),
        shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
      },
    );
  }
}
