import 'dart:async';

import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// {@template flutter_config_command}
/// `shorebird flutter config`
/// Manage your Shorebird Flutter Config.
/// {@endtemplate}
class FlutterConfigCommand extends ShorebirdProxyCommand {
  @override
  String get description =>
      '''Configure Flutter settings. This proxies to the underlying `flutter config` command.''';

  @override
  String get name => 'config';

  @override
  FutureOr<int> run() =>
      shorebirdProcess.stream('flutter', ['config', ...results.rest]);
}
