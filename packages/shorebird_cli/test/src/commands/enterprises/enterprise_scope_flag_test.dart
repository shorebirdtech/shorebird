import 'package:shorebird_cli/src/commands/apps/apps_list_command.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs_list_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'enterprise_test_harness.dart';

/// The command tests stub `results['enterprise']`, so these parse real
/// arguments to check that each command still declares the flag.
void main() {
  useTempWorkingDirectory();

  final commands = <String, ShorebirdCommand Function()>{
    'orgs list': OrgsListCommand.new,
    'apps list': AppsListCommand.new,
    'members list': MembersListCommand.new,
    'members set-role': MembersSetRoleCommand.new,
    'members remove': MembersRemoveCommand.new,
  };

  for (final MapEntry(key: name, value: create) in commands.entries) {
    test('$name takes --enterprise', () {
      final command = EnterpriseHarness().run(create);
      expect(
        command.argParser.parse(['--enterprise']).flag('enterprise'),
        isTrue,
      );
      expect(command.argParser.parse([]).flag('enterprise'), isFalse);
    });
  }
}
