import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class IosDeviceInfo {
  IosDeviceInfo({
    required this.name,
    required this.udid,
    required this.iosVersion,
  });

  static IosDeviceInfo fromJson(Json json) {
    return IosDeviceInfo(
      // ignore: avoid_dynamic_calls
      name: json['deviceProperties']['name'] as String,
      // ignore: avoid_dynamic_calls
      udid: json['hardwareProperties']['udid'] as String,
      iosVersion:
          // ignore: avoid_dynamic_calls
          Version.parse(json['deviceProperties']['osVersionNumber'] as String),
    );
  }

  final String name;
  final String udid;
  final Version iosVersion;

  @override
  String toString() =>
      '$IosDeviceInfo(name: $name, udid: $udid, iosVersion: $iosVersion)';
}
