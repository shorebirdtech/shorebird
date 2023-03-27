import 'package:cli_util/cli_util.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/command_runner.dart';

final String shorebirdConfigDir = () {
  final configHome = testApplicationConfigHome ?? applicationConfigHome;
  return configHome(executableName);
}();

/// Test applicationConfigHome which should
/// only be used for testing purposes.
@visibleForTesting
String Function(String)? testApplicationConfigHome;
