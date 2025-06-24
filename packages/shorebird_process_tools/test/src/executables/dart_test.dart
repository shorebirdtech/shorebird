import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_process_tools/shorebird_process_tools.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('scoped', () {
    test('has access to dart reference', () {
      expect(
        runScoped(() => dart, values: {dartRef}),
        isA<Dart>(),
      );
    });
  });

  group(Dart, () {
    late ProcessWrapper processWrapper;
    late ShorebirdProcessResult processResult;
    late Dart dart;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          processRef.overrideWith(() => processWrapper),
        },
      );
    }

    setUp(() {
      processWrapper = MockProcessWrapper();
      processResult = MockShorebirdProcessResult();
      dart = Dart();

      when(() => processResult.exitCode).thenReturn(0);
      when(() => processResult.stdout).thenReturn('');
      when(() => processResult.stderr).thenReturn('');

      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => processResult);
    });

    test('has correct executable name', () {
      expect(Dart.executable, equals('dart'));
    });

    group('format', () {
      setUp(() {
        when(() => processResult.exitCode).thenReturn(0);
        when(() => processResult.stdout).thenReturn('');
      });

      test('runs dart format with correct arguments', () async {
        await runWithOverrides(
          () => dart.format(path: '/test/path'),
        );

        verify(
          () => processWrapper.run(
            'dart',
            ['format', '/test/path'],
          ),
        ).called(1);
      });

      test('includes --set-exit-if-changed when specified', () async {
        await runWithOverrides(
          () => dart.format(
            path: '/test/path',
            setExitIfChanged: true,
          ),
        );

        verify(
          () => processWrapper.run(
            'dart',
            ['format', '--set-exit-if-changed', '/test/path'],
          ),
        ).called(1);
      });

      group('when format succeeds', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(0);
          when(() => processResult.stdout).thenReturn('Formatted 2 files');
        });

        test('returns correct result', () async {
          final result = await runWithOverrides(
            () => dart.format(path: '/test/path'),
          );

          expect(result.isFormattedCorrectly, isTrue);
          expect(result.output, equals('Formatted 2 files'));
        });
      });

      group('when format fails', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(1);
          when(() => processResult.stdout).thenReturn('Format failed');
        });

        test('returns correct result', () async {
          final result = await runWithOverrides(
            () => dart.format(path: '/test/path'),
          );

          expect(result.isFormattedCorrectly, isFalse);
          expect(result.output, equals('Format failed'));
        });
      });
    });

    group('pubGet', () {
      setUp(() {
        when(() => processResult.exitCode).thenReturn(0);
        when(
          () => processResult.stdout,
        ).thenReturn('Resolving dependencies...');
      });

      test('runs dart pub get with correct arguments', () async {
        await runWithOverrides(
          () => dart.pubGet(path: '/test/path'),
        );

        verify(
          () => processWrapper.run(
            'dart',
            ['pub', 'get'],
            workingDirectory: '/test/path',
          ),
        ).called(1);
      });

      group('when pub get succeeds', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(0);
        });

        test('completes normally', () async {
          await expectLater(
            runWithOverrides(
              () => dart.pubGet(path: '/test/path'),
            ),
            completes,
          );
        });
      });

      group('when pub get fails', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(1);
          when(() => processResult.stderr).thenReturn('Package not found');
        });

        test('throws ProcessException with correct error message', () async {
          await expectLater(
            runWithOverrides(
              () => dart.pubGet(path: '/test/path'),
            ),
            throwsA(
              isA<ProcessException>()
                  .having(
                    (e) => e.executable,
                    'executable',
                    'dart',
                  )
                  .having(
                    (e) => e.arguments,
                    'arguments',
                    ['pub', 'get'],
                  )
                  .having(
                    (e) => e.message,
                    'message',
                    'Package not found',
                  ),
            ),
          );
        });
      });
    });
  });
}
