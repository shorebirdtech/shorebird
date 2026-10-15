import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(MetricsCommand, () {
    late MetricsCommand command;

    setUp(() {
      command = MetricsCommand();
    });

    test('has the correct name', () {
      expect(command.name, equals('metrics'));
    });

    test('mentions the web console name in its description', () {
      expect(command.description, contains('"Insights"'));
    });

    test('has one subcommand per metric', () {
      expect(
        command.subcommands.keys,
        unorderedEquals([
          'active-hours',
          'adoption',
          'downloads',
          'heatmap',
          'installs',
          'new-devices',
          'users',
          'versions',
        ]),
      );
    });
  });
}
