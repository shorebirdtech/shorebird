import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

import '../../mocks.dart';

/// The organization the service account tests act in.
final acme = OrganizationMembership(
  organization: Organization(
    id: 42,
    name: 'Acme Corp',
    organizationType: OrganizationType.team,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  role: Role.admin,
);

/// A service account in [acme].
final releaseBot = ServiceAccount(
  id: 383,
  organizationId: 42,
  name: 'release-bot',
  label: 'release-bot[bot]',
  role: ServiceAccountRole.developer,
  createdAt: DateTime.utc(2026, 10),
  createdByUserId: 1,
  createdByEmail: 'admin@acme.com',
  lastAuthAt: DateTime.utc(2026, 10, 20),
);

/// A key of [releaseBot].
final ciKey = ServiceAccountKey(
  id: 12,
  name: 'ci',
  createdAt: DateTime.utc(2026, 10),
  lastUsedAt: null,
  expiresAt: DateTime.utc(2027, 10),
  scopes: const [],
);

/// Mocks and a scope for running a service account command against [acme],
/// which owns [releaseBot], which has [ciKey].
class ServiceAccountTestContext {
  ServiceAccountTestContext() {
    when(
      () => validator.validatePreconditions(
        checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
      ),
    ).thenAnswer((_) async {});
    when(wrapper.getOrganizationMemberships).thenAnswer((_) async => [acme]);
    when(
      () => wrapper.getServiceAccounts(organizationId: 42),
    ).thenAnswer((_) async => [releaseBot]);
    when(
      () => wrapper.getServiceAccountKeys(
        organizationId: 42,
        serviceAccountId: 383,
      ),
    ).thenAnswer((_) async => [ciKey]);
    when(env.getShorebirdYaml).thenReturn(null);
    when(() => env.canAcceptUserInput).thenReturn(false);
    when(() => env.hostedEnvironment).thenReturn(null);
  }

  final CodePushClientWrapper wrapper = MockCodePushClientWrapper();
  final ShorebirdEnv env = MockShorebirdEnv();
  final ShorebirdLogger logger = MockShorebirdLogger();
  final ShorebirdValidator validator = MockShorebirdValidator();

  /// Runs [body] with these mocks in scope.
  R run<R>(R Function() body, {bool json = false}) => runScoped(
    body,
    values: {
      codePushClientWrapperRef.overrideWith(() => wrapper),
      isJsonModeRef.overrideWith(() => json),
      loggerRef.overrideWith(() => logger),
      shorebirdEnvRef.overrideWith(() => env),
      shorebirdValidatorRef.overrideWith(() => validator),
    },
  );

  /// Parses [args] for [command], then runs it.
  Future<int> runCommand(
    ShorebirdCommand command,
    List<String> args, {
    bool json = false,
  }) {
    command.testArgResults = command.argParser.parse(args);
    return run(() async => (await command.run())!, json: json);
  }

  /// Every line logged at info level.
  List<String> get infoLines =>
      verify(() => logger.info(captureAny())).captured.cast<String>();

  /// The exit code for success.
  int get ok => ExitCode.success.code;
}
