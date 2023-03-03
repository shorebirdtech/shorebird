import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_code_push_api_client/shorebird_code_push_api_client.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockShorebirdCodePushApiClient extends Mock
    implements ShorebirdCodePushApiClient {}

void main() {
  group('publish', () {
    late Logger logger;
    late _MockShorebirdCodePushApiClient codePushApiClient;
    late ShorebirdCliCommandRunner commandRunner;

    setUp(() {
      logger = _MockLogger();
      codePushApiClient = _MockShorebirdCodePushApiClient();
      commandRunner = ShorebirdCliCommandRunner(
        logger: logger,
        codePushApiClient: codePushApiClient,
      );
    });

    test('throws usage error when no file path is specified.', () async {
      final exitCode = await commandRunner.run(['publish']);
      verify(
        () => logger.err('A single file path must be specified.'),
      ).called(1);
      expect(exitCode, ExitCode.usage.code);
    });

    test('throws usage error when multiple args are passed.', () async {
      final exitCode = await commandRunner.run(['publish', 'arg1', 'arg2']);
      verify(
        () => logger.err('A single file path must be specified.'),
      ).called(1);
      expect(exitCode, ExitCode.usage.code);
    });

    test('throws no input error when file is not found.', () async {
      final exitCode = await commandRunner.run([
        'publish',
        'missing.txt',
      ]);
      verify(() => logger.err('File not found: missing.txt')).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws error when release fails.', () async {
      const error = 'something went wrong';
      when(() => codePushApiClient.createRelease(any())).thenThrow(error);
      final release = p.join('test', 'fixtures', 'release.txt');
      final exitCode = await commandRunner.run(['publish', release]);
      verify(() => logger.err('Failed to deploy: $error')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('succeeds when release is successful.', () async {
      when(
        () => codePushApiClient.createRelease(any()),
      ).thenAnswer((_) async {});
      final release = p.join('test', 'fixtures', 'release.txt');
      final exitCode = await commandRunner.run(['publish', release]);
      verify(() => logger.success('Deployed $release!')).called(1);
      expect(exitCode, ExitCode.success.code);
    });
  });
}
