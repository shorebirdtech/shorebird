import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/release_new/android_releaser.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(AndroidReleaser, () {
    late ArgParser argParser;
    late ArgResults argResults;
    late Logger logger;

    setUp(() {
      argParser = MockArgParser();
      argResults = MockArgResults();
      logger = MockLogger();
    });

    test('android release pipeline ...', () async {
      // TODO: Implement test
    });
  });
}
