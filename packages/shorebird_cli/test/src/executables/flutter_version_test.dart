import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/executables/flutter_version.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('flutterVersionFromSystemFlutter', () {
    test('returns the Flutter version from the output', () {
      final process = MockShorebirdProcess();
      const output = '''
Flutter 3.32.4 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 6fba2447e9 (5 weeks ago) • 2025-06-12 19:03:56 -0700
Engine • revision 8cd19e509d (5 weeks ago) • 2025-06-12 16:30:12 -0700
Tools • Dart 3.8.1 • DevTools 2.45.1
      ''';
      when(() => process.runSync('flutter', ['--version'])).thenReturn(
        const ShorebirdProcessResult(
          exitCode: 0,
          stdout: output,
          stderr: '',
        ),
      );
      expect(flutterVersionFromSystemFlutter(process), '3.32.4');
    });

    test(
      'throws an exception if the output does not contain a Flutter version',
      () {
        final process = MockShorebirdProcess();
        const output = '''
Framework • revision 6fba2447e9 (5 weeks ago) • 2025-06-12 19:03:56 -0700
Engine • revision 8cd19e509d (5 weeks ago) • 2025-06-12 16:30:12 -0700
Tools • Dart 3.8.1 • DevTools 2.45.1
      ''';
        when(() => process.runSync('flutter', ['--version'])).thenReturn(
          const ShorebirdProcessResult(
            exitCode: 0,
            stdout: output,
            stderr: '',
          ),
        );
        expect(
          () => flutterVersionFromSystemFlutter(process),
          throwsA(isA<Exception>()),
        );
      },
    );
    test('throws an exception if the process fails', () {
      final process = MockShorebirdProcess();
      when(() => process.runSync('flutter', ['--version'])).thenThrow(
        Exception('Failed to run flutter'),
      );
      expect(
        () => flutterVersionFromSystemFlutter(process),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('flutterVersionFromFVMFlutter', () {
    test('returns the Flutter version from the output', () {
      final process = MockShorebirdProcess();
      const output = '''
Flutter 3.32.4 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 6fba2447e9 (5 weeks ago) • 2025-06-12 19:03:56 -0700
Engine • revision 8cd19e509d (5 weeks ago) • 2025-06-12 16:30:12 -0700
Tools • Dart 3.8.1 • DevTools 2.45.1
      ''';
      when(() => process.runSync('fvm', ['flutter', '--version'])).thenReturn(
        const ShorebirdProcessResult(
          exitCode: 0,
          stdout: output,
          stderr: '',
        ),
      );
      expect(flutterVersionFromFVMFlutter(process), '3.32.4');
    });

    test(
      'throws an exception if the output does not contain a Flutter version',
      () {
        final process = MockShorebirdProcess();
        const output = '''
Framework • revision 6fba2447e9 (5 weeks ago) • 2025-06-12 19:03:56 -0700
Engine • revision 8cd19e509d (5 weeks ago) • 2025-06-12 16:30:12 -0700
Tools • Dart 3.8.1 • DevTools 2.45.1
      ''';
        when(() => process.runSync('fvm', ['flutter', '--version'])).thenReturn(
          const ShorebirdProcessResult(
            exitCode: 0,
            stdout: output,
            stderr: '',
          ),
        );
        expect(
          () => flutterVersionFromFVMFlutter(process),
          throwsA(isA<Exception>()),
        );
      },
    );
    test('throws an exception if the process fails', () {
      final process = MockShorebirdProcess();
      when(() => process.runSync('fvm', ['flutter', '--version'])).thenThrow(
        Exception('Failed to run fvm flutter'),
      );
      expect(
        () => flutterVersionFromFVMFlutter(process),
        throwsA(isA<Exception>()),
      );
    });
  });
}
