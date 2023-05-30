import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group(ShorebirdCommand, () {
    test('passes logger to codePushClient in default builder', () {
      final logger = Logger();
      final command = TestCommand(logger: logger);
      final codePushClient = command.buildCodePushClient(
        httpClient: _MockHttpClient(),
      );
      expect(codePushClient.logger, logger);
    });
  });
}

class TestCommand extends ShorebirdCommand {
  TestCommand({required super.logger});

  @override
  String get description => 'A test command';

  @override
  String get name => 'test';
}
