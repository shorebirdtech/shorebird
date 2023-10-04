import 'dart:convert';

import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

void main() {
  group(AppleDevice, () {
    group('fromJson', () {
      test('deserializes from valid json', () {
        const jsonString = '''
{
  "deviceProperties": {
    "name": "Bryan Oltman’s iPhone",
    "osVersionNumber": "17.0.2"
  },
  "hardwareProperties": {
    "platform": "iOS"
  },
  "identifier": "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF"
}
''';

        final device = AppleDevice.fromJson(json.decode(jsonString) as Json);
        expect(device.name, equals('Bryan Oltman’s iPhone'));
        expect(
          device.identifier,
          equals('DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF'),
        );
        expect(device.iosVersionString, equals('17.0.2'));
        expect(device.platform, equals('iOS'));
      });

      test(
          '''throws exception when attempting to deserialize from incomplete json''',
          () {
        const jsonString = '''
{
  "deviceProperties": {
  },
  "hardwareProperties": {
  },
  "identifier": 1234
}
''';
        final device = AppleDevice.fromJson(json.decode(jsonString) as Json);
        expect(device.name, equals('Bryan Oltman’s iPhone'));
        expect(
          device.identifier,
          equals('DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF'),
        );
        expect(device.iosVersionString, equals('17.0.2'));
        expect(device.platform, equals('iOS'));
      });
    });
  });
}
