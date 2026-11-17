// cspell:words lfanew
import 'dart:io';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/abi.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';
import '../../helpers.dart';
import '../../mocks.dart';

/// A minimal Windows executable header: a DOS header whose e_lfanew points
/// at a PE signature followed by [machine].
Uint8List peHeader(int machine) {
  final bytes = ByteData(0x80)
    ..setUint8(0, 0x4d) // M
    ..setUint8(1, 0x5a) // Z
    ..setUint32(0x3c, 0x40, Endian.little)
    ..setUint8(0x40, 0x50) // P
    ..setUint8(0x41, 0x45) // E
    ..setUint16(0x44, machine, Endian.little);
  return bytes.buffer.asUint8List();
}

void main() {
  useTempWorkingDirectory();
  R runWithOverrides<R>(R Function() body) {
    return runScoped(
      body,
      values: {windowsRef.overrideWith(Windows.new)},
    );
  }

  group('peMachine', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync());
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('reads the machine of a Windows executable', () {
      final file = File(p.join(tempDir.path, 'dart.exe'))
        ..writeAsBytesSync(peHeader(0xaa64));
      expect(peMachine(file), 0xaa64);
    });

    test('is null for a missing file', () {
      expect(peMachine(File(p.join(tempDir.path, 'missing.exe'))), isNull);
    });

    test('is null for a file that is not an executable', () {
      final file = File(p.join(tempDir.path, 'dart.exe'))
        ..writeAsStringSync('not an executable');
      expect(peMachine(file), isNull);
    });

    test('is null when the PE signature is missing', () {
      final bytes = peHeader(0x8664)..[0x40] = 0;
      final file = File(p.join(tempDir.path, 'dart.exe'))
        ..writeAsBytesSync(bytes);
      expect(peMachine(file), isNull);
    });
  });

  group('windowsTargetArch', () {
    late LocalAbi abi;
    late ShorebirdEnv shorebirdEnv;
    late Directory flutterDirectory;

    Arch targetArch() => runScoped(
      () => windowsTargetArch,
      values: {
        abiRef.overrideWith(() => abi),
        shorebirdEnvRef.overrideWith(() => shorebirdEnv),
      },
    );

    void writeFlutterDart(int machine) {
      File(
          p.join(
            flutterDirectory.path,
            'bin',
            'cache',
            'dart-sdk',
            'bin',
            'dart.exe',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsBytesSync(peHeader(machine));
    }

    setUp(() {
      abi = MockAbi();
      shorebirdEnv = MockShorebirdEnv();
      flutterDirectory = Directory.systemTemp.createTempSync();
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => abi.hostArchitecture).thenReturn('arm64');
    });

    test("is arm64 when Flutter's Dart is arm64", () {
      when(() => abi.hostArchitecture).thenReturn('x64');
      writeFlutterDart(0xaa64);
      expect(targetArch(), Arch.arm64);
    });

    test("is x64 when Flutter's Dart is x64, even on an arm64 machine", () {
      writeFlutterDart(0x8664);
      expect(targetArch(), Arch.x86_64);
    });

    test("is the machine's when Flutter's Dart can't be read", () {
      expect(targetArch(), Arch.arm64);
      when(() => abi.hostArchitecture).thenReturn('x64');
      expect(targetArch(), Arch.x86_64);
    });
  });

  group(Windows, () {
    group('findExecutable', () {
      const projectName = 'my_app';
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync();
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      group('when no executables exist', () {
        test('throws an exception', () {
          expect(
            () => runWithOverrides(
              () => windows.findExecutable(
                releaseDirectory: tempDir,
                projectName: projectName,
              ),
            ),
            throwsA(isA<Exception>()),
          );
        });
      });

      group('when an exact match exists', () {
        late File app;

        setUp(() {
          app = File(p.join(tempDir.path, '$projectName.exe'))..createSync();
          File(p.join(tempDir.path, 'other.exe')).createSync();
        });

        test('returns it', () {
          final executable = runWithOverrides(
            () => windows.findExecutable(
              releaseDirectory: tempDir,
              projectName: projectName,
            ),
          );
          expect(executable.path, equals(app.path));
        });
      });

      group('when an exact match does not exist', () {
        late File app;

        setUp(() {
          final other = File(p.join(tempDir.path, 'other.exe'))..createSync();
          app = File(p.join(tempDir.path, '$projectName.exe'))..createSync();
          // Set modification times so my_app is newer than other.
          other.setLastModifiedSync(DateTime(2024));
          app.setLastModifiedSync(DateTime(2025));
        });

        test('returns most recently modified executable', () {
          final selected = runWithOverrides(
            () => windows.findExecutable(
              releaseDirectory: tempDir,
              projectName: 'runner',
            ),
          );
          expect(selected.path, equals(app.path));
        });
      });
    });
  });
}
