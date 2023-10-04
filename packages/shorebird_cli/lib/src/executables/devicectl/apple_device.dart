import 'package:json_path/json_path.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class AppleDevice {
  AppleDevice({
    required this.name,
    required this.identifier,
    required this.iosVersionString,
    required this.platform,
  });

  static AppleDevice fromJson(Json json) {
    return AppleDevice(
      name: JsonPath(r'$.deviceProperties.name').read(json).first.value!
          as String,
      identifier: JsonPath(r'$.identifier').read(json).first.value! as String,
      iosVersionString: JsonPath(r'$.deviceProperties.osVersionNumber')
          .read(json)
          .first
          .value! as String,
      platform: JsonPath(r'$.hardwareProperties.platform')
          .read(json)
          .first
          .value! as String,
    );
  }

  /// Human-readable name of the device (e.g., "Joe's iPhone").
  final String name;

  /// The device's unique identifier.
  final String identifier;

  /// The device's iOS version as a string (e.g., "14.4.1").
  final String iosVersionString;

  /// The device's platform (e.g., "iOS").
  final String platform;

  @override
  String toString() =>
      '''$AppleDevice(name: $name, identifier: $identifier, iosVersion: $iosVersionString)''';
}
