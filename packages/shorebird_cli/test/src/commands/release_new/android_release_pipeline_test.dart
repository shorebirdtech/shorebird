import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/release_new/android_release_pipeline.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(AndroidReleasePipline, () {
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
