import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

import '../../helpers.dart';
import '../../mocks.dart';

/// The app id the harness resolves from shorebird.yaml.
const metricsTestAppId = 'test-app-id';

/// A fixed window used in metrics fixtures.
final metricsTestRange = MetricsRange(
  start: DateTime.utc(2026, 9, 17),
  end: DateTime.utc(2026, 10, 15),
);

/// Shared mocks and scoping for `shorebird metrics` subcommand tests.
///
/// Options are read from [args]; set entries there to simulate flags.
class MetricsTestHarness {
  /// Creates the mocks. Call [setUp] from the test's `setUp`.
  MetricsTestHarness();

  final args = <String, Object?>{};
  late ArgResults argResults;
  late CodePushClientWrapper codePushClientWrapper;
  late CodePushClient codePushClient;
  late ShorebirdEnv shorebirdEnv;
  late ShorebirdValidator shorebirdValidator;
  late ShorebirdLogger logger;
  late Progress progress;

  /// Runs [body] with the harness's mocks in scope.
  R run<R>(R Function() body, {bool jsonMode = false}) {
    return runScoped(
      body,
      values: {
        codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
        isJsonModeRef.overrideWith(() => jsonMode),
        loggerRef.overrideWith(() => logger),
        shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
      },
    );
  }

  /// Runs [command] in `--json` mode and returns its exit code and envelope.
  Future<({int exitCode, Map<String, dynamic> json})> runJson(
    ShorebirdCommand command,
  ) => captureJson(() async => (await run(command.run, jsonMode: true))!);

  /// Builds [create] in scope and attaches the harness's [argResults].
  T createCommand<T extends ShorebirdCommand>(T Function() create) =>
      run(create)
        ..testArgResults = argResults
        ..testRunner = usageRunner();

  /// Stubs the mocks for a successful run against [metricsTestAppId].
  void setUp() {
    args.clear();
    argResults = MockArgResults();
    codePushClientWrapper = MockCodePushClientWrapper();
    codePushClient = MockCodePushClient();
    logger = MockShorebirdLogger();
    progress = MockProgress();
    shorebirdEnv = MockShorebirdEnv();
    shorebirdValidator = MockShorebirdValidator();

    when(() => argResults[any()]).thenAnswer(
      (invocation) => args[invocation.positionalArguments.first as String],
    );
    when(() => argResults.wasParsed(any())).thenAnswer(
      (invocation) =>
          args[invocation.positionalArguments.first as String] != null,
    );
    when(() => argResults.rest).thenReturn([]);
    when(() => logger.progress(any())).thenReturn(progress);
    when(
      () => shorebirdEnv.getShorebirdYaml(),
    ).thenReturn(const ShorebirdYaml(appId: metricsTestAppId));
    when(
      () => shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => codePushClientWrapper.codePushClient,
    ).thenReturn(codePushClient);
  }
}

/// The lines [harness]'s logger printed with `info`, in order.
List<String> loggedLines(MetricsTestHarness harness) => verify(
  () => harness.logger.info(captureAny()),
).captured.cast<String>();
