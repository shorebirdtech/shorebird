import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockHttpClient extends Mock implements http.Client {}

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  group('publish', () {
    late Logger logger;
    late http.Client httpClient;
    late ShorebirdCliCommandRunner commandRunner;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      logger = _MockLogger();
      httpClient = _MockHttpClient();
      commandRunner = ShorebirdCliCommandRunner(
        logger: logger,
        httpClient: httpClient,
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
      const statusCode = HttpStatus.internalServerError;
      const reasonPhrase = 'something went wrong';
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          statusCode,
          reasonPhrase: reasonPhrase,
        ),
      );
      final release = p.join('test', 'fixtures', 'release.txt');
      final exitCode = await commandRunner.run(['publish', release]);
      verify(
        () => logger.err('Failed to deploy: $statusCode $reasonPhrase'),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('succeeds when release is successful.', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          HttpStatus.created,
        ),
      );
      final release = p.join('test', 'fixtures', 'release.txt');
      final exitCode = await commandRunner.run(['publish', release]);
      verify(() => logger.success('Deployed $release!')).called(1);
      expect(exitCode, ExitCode.success.code);
    });
  });
}
