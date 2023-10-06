import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:test/test.dart';

void main() {
  group(AppleDevice, () {
    group('osVersion', () {
      const identifier = 'DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF';
      const deviceName = "Joe's iPhone";
      const connectionProperties =
          ConnectionProperties(tunnelState: 'disconnected');
      const hardwareProperties = HardwareProperties(platform: 'iOS');

      late AppleDevice device;

      group('when version string is null', () {
        setUp(() {
          device = const AppleDevice(
            identifier: identifier,
            deviceProperties: DeviceProperties(name: deviceName),
            hardwareProperties: hardwareProperties,
            connectionProperties: connectionProperties,
          );
        });

        test('returns null', () {
          expect(device.osVersion, isNull);
        });
      });

      group('when version string not parseable', () {
        setUp(() {
          device = const AppleDevice(
            identifier: identifier,
            deviceProperties: DeviceProperties(
              name: deviceName,
              osVersionNumber: 'unparseable version number',
            ),
            hardwareProperties: hardwareProperties,
            connectionProperties: connectionProperties,
          );
        });

        test('returns null', () {
          expect(device.osVersion, isNull);
        });
      });

      group('when version string is valid', () {
        setUp(() {
          device = const AppleDevice(
            identifier: identifier,
            deviceProperties: DeviceProperties(
              name: deviceName,
              osVersionNumber: '1.2.3',
            ),
            hardwareProperties: hardwareProperties,
            connectionProperties: connectionProperties,
          );
        });

        test('returns a Version', () {
          expect(device.osVersion, equals(Version(1, 2, 3)));
        });
      });
    });
  });
}
