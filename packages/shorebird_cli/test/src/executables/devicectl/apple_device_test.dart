import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:test/test.dart';

void main() {
  group(AppleDevice, () {
    const udid = '12345678-1234567890ABCDEF';
    const deviceName = "Joe's iPhone";
    const connectionProperties = ConnectionProperties(
      transportType: 'wired',
      tunnelState: 'disconnected',
    );
    const deviceProperties = DeviceProperties(
      name: deviceName,
      osVersionNumber: '17.1',
    );
    const hardwareProperties = HardwareProperties(
      platform: 'iOS',
      udid: udid,
    );

    late AppleDevice device;

    setUp(() {
      device = const AppleDevice(
        deviceProperties: deviceProperties,
        hardwareProperties: hardwareProperties,
        connectionProperties: connectionProperties,
      );
    });

    group('toString', () {
      test('includes name, OS version, and UDID', () {
        expect(
          device.toString(),
          equals('$deviceName (${deviceProperties.osVersionNumber} $udid)'),
        );
      });
    });

    group('osVersion', () {
      group('when version string is null', () {
        test('returns null', () {
          expect(device.osVersion, isNull);
        });
      });

      group('when version string not parseable', () {
        setUp(() {
          device = const AppleDevice(
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

    group('isWired', () {
      group('when connectionProperties.transportType is "wired"', () {
        setUp(() {
          device = const AppleDevice(
            deviceProperties: deviceProperties,
            hardwareProperties: hardwareProperties,
            connectionProperties: ConnectionProperties(
              tunnelState: 'disconnected',
              transportType: 'wired',
            ),
          );
        });

        test('returns true', () {
          expect(device.isWired, isTrue);
        });
      });

      group('when connectionProperties.transportType is "network"', () {
        setUp(() {
          device = const AppleDevice(
            deviceProperties: deviceProperties,
            hardwareProperties: hardwareProperties,
            connectionProperties: ConnectionProperties(
              tunnelState: 'disconnected',
              transportType: 'network',
            ),
          );
        });

        test('returns false', () {
          expect(device.isWired, isFalse);
        });
      });
    });
  });
}
