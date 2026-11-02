import 'dart:io';

import 'package:path/path.dart' as p;

/// A platform whose AOT build can be recognized in a Flutter build folder.
enum KernelBuildPlatform {
  /// Android (`flutter build apk/appbundle/aar`).
  android('Android'),

  /// iOS (`flutter build ipa/ios/ios-framework`).
  ios('iOS'),

  /// macOS (`flutter build macos`).
  macos('macOS');

  const KernelBuildPlatform(this.displayName);

  /// The platform's name as shown to users.
  final String displayName;
}

/// What a `.dart_tool/flutter_build/<hash>/` folder records about the build
/// that ran in it.
///
/// Flutter's build system writes each build configuration (target platform,
/// build mode, defines, ...) to its own `flutter_build/<hash>/` folder, and
/// writes `<target name>.stamp` there when each build target finishes. The
/// `app.dill` in that folder is the kernel that configuration compiled, and
/// for an AOT build it is compiled with `--target-os` for that platform, which
/// folds `Platform.isIOS`, `Platform.isAndroid`, etc. to constants. So the
/// stamp of the platform's AOT target says which OS the folder's `app.dill`
/// was compiled for.
///
/// The kernel itself doesn't record `--target-os`; it only leaves folded
/// constants scattered through the program, which aren't a reliable signal.
class KernelBuildFolder {
  KernelBuildFolder._({required this.folder, required this.stampNames});

  /// Reads the build folder that holds [kernelFile], or returns `null` if
  /// [kernelFile] isn't an `app.dill` directly inside
  /// `.dart_tool/flutter_build/<hash>/` (e.g. the copy Shorebird's Flutter
  /// writes to `build/<platform>/shorebird_kernel/app.dill`, whose path
  /// already names the platform).
  static KernelBuildFolder? forKernel(File kernelFile) {
    final folder = kernelFile.parent;
    if (p.basename(folder.parent.path) != 'flutter_build' ||
        p.basename(folder.parent.parent.path) != '.dart_tool') {
      return null;
    }
    final stampNames = folder.existsSync()
        ? folder
              .listSync()
              .whereType<File>()
              .map((f) => p.basename(f.path))
              .where((name) => name.endsWith('.stamp'))
              .map(p.basenameWithoutExtension)
              .toSet()
        : <String>{};
    return KernelBuildFolder._(folder: folder, stampNames: stampNames);
  }

  /// The `flutter_build/<hash>/` folder.
  final Directory folder;

  /// The names of the build targets that finished in [folder].
  final Set<String> stampNames;

  /// The platforms whose AOT target finished in [folder].
  ///
  /// The target names are those in flutter_tools'
  /// `lib/src/build_system/targets/`, unchanged from Flutter 3.24 (the oldest
  /// Flutter Shorebird supports for iOS) to today:
  /// - iOS: `AotAssemblyRelease` / `AotAssemblyProfile` (`ios.dart`).
  /// - macOS: `CompileMacOSFramework` (`macos.dart`).
  /// - Android: `AndroidAot`, named `android_aot_<mode>_<platform>`
  ///   (`android.dart`).
  Set<KernelBuildPlatform> get aotPlatforms => {
    if (stampNames.contains('aot_assembly_release') ||
        stampNames.contains('aot_assembly_profile'))
      KernelBuildPlatform.ios,
    if (stampNames.contains('compile_macos_framework'))
      KernelBuildPlatform.macos,
    if (stampNames.any((name) => name.startsWith('android_aot_')))
      KernelBuildPlatform.android,
  };
}
