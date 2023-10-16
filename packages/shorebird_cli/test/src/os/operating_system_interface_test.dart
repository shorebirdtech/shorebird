import 'package:shorebird_cli/src/os/os.dart';
import 'package:test/test.dart';

void main() {
  group(OperatingSystemInterface, () {
    group('on macOS/Linux', () {
      group('which', () {
        group('when no executable is found on path', () {
          test('returns null', () {});
        });

        group('when executable is found on path', () {
          test('returns path to executable', () {});
        });
      });
    });

    group('on Windows', () {
      group('which', () {
        group('when no executable is found on path', () {
          test('returns null', () {});
        });

        group('when executable is found on path', () {
          test('returns path to executable', () {});
        });

        group('when multiple executables are found on path', () {
          test('returns path to executable', () {});
        });
      });
    });
  });
}
