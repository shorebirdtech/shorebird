import 'package:shorebird_ci/src/activate_pin.dart';
import 'package:test/test.dart';

void main() {
  test('reads the version off an activate line', () {
    final pins = findActivatePins('''
jobs:
  changes:
    steps:
      - run: dart pub global activate shorebird_ci 0.2.5
''');
    expect(pins.versions, {'0.2.5'});
    expect(pins.hasUnpinned, isFalse);
  });

  test('an activate line with no version is unpinned', () {
    final pins = findActivatePins(
      '      - run: dart pub global activate shorebird_ci\n',
    );
    expect(pins.versions, isEmpty);
    expect(pins.hasUnpinned, isTrue);
  });

  test('a commented-out activate line is not one CI runs', () {
    final pins = findActivatePins(
      '      # - run: dart pub global activate shorebird_ci 0.1.0\n',
    );
    expect(pins.versions, isEmpty);
    expect(pins.hasUnpinned, isFalse);
  });

  test('another package whose name starts the same is not shorebird_ci', () {
    final pins = findActivatePins(
      '      - run: dart pub global activate shorebird_cli 1.0.0\n',
    );
    expect(pins.versions, isEmpty);
    expect(pins.hasUnpinned, isFalse);
  });

  test('a flag after the package name is not a version', () {
    final pins = findActivatePins(
      '      - run: dart pub global activate shorebird_ci --overwrite\n',
    );
    expect(pins.versions, isEmpty);
    expect(pins.hasUnpinned, isTrue);
  });

  test('no activate line at all', () {
    final pins = findActivatePins('name: CI\non: [push]\n');
    expect(pins.versions, isEmpty);
    expect(pins.hasUnpinned, isFalse);
  });
}
