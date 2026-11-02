import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/commands/patch/kernel_build_folder.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(KernelBuildFolder, () {
    late Directory projectRoot;

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync();
      addTearDown(() => projectRoot.deleteSync(recursive: true));
    });

    /// Creates `.dart_tool/flutter_build/<hash>/` holding an app.dill and a
    /// `<name>.stamp` for each of [stamps], and returns the app.dill.
    File kernelInBuildFolder(List<String> stamps, {String hash = 'abc123'}) {
      final folder = Directory(
        p.join(projectRoot.path, '.dart_tool', 'flutter_build', hash),
      )..createSync(recursive: true);
      for (final stamp in stamps) {
        File(p.join(folder.path, '$stamp.stamp')).writeAsStringSync('{}');
      }
      return File(p.join(folder.path, 'app.dill'))..writeAsStringSync('dill');
    }

    // The stamp lists below are what `flutter build` (Shorebird's Flutter,
    // Dart 3.13.5) left in each build folder for a new app.
    const sharedStamps = [
      'build_hooks',
      'gen_dart_plugin_registrant',
      'gen_localizations',
      'install_code_assets',
      'kernel_snapshot_program',
      'link_hooks',
    ];

    test('recognizes an iOS release build folder', () {
      final kernel = kernelInBuildFolder([
        ...sharedStamps,
        'aot_assembly_release',
        'release_ios_bundle_flutter_assets',
        'release_unpack_ios',
      ]);
      expect(
        KernelBuildFolder.forKernel(kernel)!.aotPlatforms,
        equals({KernelBuildPlatform.ios}),
      );
    });

    test('recognizes an iOS profile build folder', () {
      final kernel = kernelInBuildFolder(['aot_assembly_profile']);
      expect(
        KernelBuildFolder.forKernel(kernel)!.aotPlatforms,
        equals({KernelBuildPlatform.ios}),
      );
    });

    test('recognizes a macOS release build folder', () {
      final kernel = kernelInBuildFolder([
        ...sharedStamps,
        'compile_macos_framework',
        'release_macos_bundle_flutter_assets',
        'release_unpack_macos',
      ]);
      expect(
        KernelBuildFolder.forKernel(kernel)!.aotPlatforms,
        equals({KernelBuildPlatform.macos}),
      );
    });

    test('recognizes an Android release build folder', () {
      final kernel = kernelInBuildFolder([
        ...sharedStamps,
        'android_aot_bundle_release_android-arm64',
        'android_aot_release_android-arm64',
        'aot_android_asset_bundle',
      ]);
      expect(
        KernelBuildFolder.forKernel(kernel)!.aotPlatforms,
        equals({KernelBuildPlatform.android}),
      );
    });

    test('records no AOT platform for a debug iOS build folder', () {
      final kernel = kernelInBuildFolder([
        ...sharedStamps,
        'debug_ios_bundle_flutter_assets',
        'debug_universal_framework',
        'debug_unpack_ios',
      ]);
      expect(KernelBuildFolder.forKernel(kernel)!.aotPlatforms, isEmpty);
    });

    test('records no AOT platform for a folder whose kernel step just ran', () {
      final kernel = kernelInBuildFolder(['kernel_snapshot_program']);
      expect(KernelBuildFolder.forKernel(kernel)!.aotPlatforms, isEmpty);
    });

    test('records no AOT platform when the folder was deleted', () {
      final kernel = kernelInBuildFolder([]);
      kernel.parent.deleteSync(recursive: true);
      final folder = KernelBuildFolder.forKernel(kernel)!;
      expect(folder.stampNames, isEmpty);
      expect(folder.aotPlatforms, isEmpty);
    });

    test('returns null for a kernel outside .dart_tool/flutter_build', () {
      final kernel = File(
        p.join(
          projectRoot.path,
          'build',
          'ios',
          'shorebird_kernel',
          'app.dill',
        ),
      )..createSync(recursive: true);
      expect(KernelBuildFolder.forKernel(kernel), isNull);
    });

    test('returns null for a flutter_build folder outside .dart_tool', () {
      final kernel = File(
        p.join(projectRoot.path, 'flutter_build', 'abc123', 'app.dill'),
      )..createSync(recursive: true);
      expect(KernelBuildFolder.forKernel(kernel), isNull);
    });
  });
}
