import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

mixin ShorebirdCreateAppMixin on ShorebirdConfigMixin {
  Future<App> createApp({String? appName}) async {
    late final String displayName;
    if (appName == null) {
      String? defaultAppName;
      try {
        defaultAppName = getPubspecYaml()?.name;
      } catch (_) {}

      displayName = logger.prompt(
        '${lightGreen.wrap('?')} What is your app name?',
        defaultValue: defaultAppName,
      );
    } else {
      displayName = appName;
    }

    final client = buildCodePushClient(
      apiKey: auth.currentSession!.apiKey,
      hostedUri: hostedUri,
    );

    return client.createApp(displayName: displayName);
  }
}
