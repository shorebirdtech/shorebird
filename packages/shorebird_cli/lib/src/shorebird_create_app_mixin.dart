import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

mixin ShorebirdCreateAppMixin on ShorebirdConfigMixin {
  Future<App> createApp({String? appName}) async {
    late final String displayName;
    if (appName == null) {
      String? defaultAppName;
      try {
        defaultAppName = ShorebirdEnvironment.getPubspecYaml()?.name;
      } catch (_) {}

      displayName = logger.prompt(
        '${lightGreen.wrap('?')} How should we refer to this app?',
        defaultValue: defaultAppName,
      );
    } else {
      displayName = appName;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: ShorebirdEnvironment.hostedUri,
    );

    return client.createApp(displayName: displayName);
  }
}
