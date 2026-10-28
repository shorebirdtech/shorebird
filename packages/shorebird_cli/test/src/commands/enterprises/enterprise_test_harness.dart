import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

import '../../mocks.dart';
import 'enterprise_fixtures.dart';

/// Mocks for commands run with `--enterprise-id 7`, where the user is an
/// admin of Acme (7) and a member of Globex (8).
class EnterpriseHarness {
  EnterpriseHarness() {
    when(() => argResults['enterprise-id']).thenReturn('7');
    when(() => argResults.rest).thenReturn([]);
    when(
      () => shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
      ),
    ).thenAnswer((_) async {});
    when(shorebirdEnv.getShorebirdYaml).thenReturn(null);
    when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
    when(codePushClientWrapper.getEnterprises).thenAnswer(
      (_) async => [EnterpriseFixtures.acme, EnterpriseFixtures.globex],
    );
  }

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
