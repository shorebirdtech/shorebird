import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/platform/platform.dart';

extension AndroidArch on Arch {
  /// The name of the architecture as expected by the --target-platforms flag.
  String get targetPlatformCliArg {
    switch (this) {
      case Arch.arm32:
        return 'android-arm';
      case Arch.arm64:
        return 'android-arm64';
      case Arch.x86_64:
        return 'android-x64';
    }
  }

  /// Where in the build directory artifacts for this architecture are stored.
  String get androidBuildPath {
    switch (this) {
      case Arch.arm32:
        return 'armeabi-v7a';
      case Arch.arm64:
        return 'arm64-v8a';
      case Arch.x86_64:
        return 'x86_64';
    }
  }

  /// The subdirectory used for local engine builds
  /// (i.e., engine/src/out/[androidEnginePath]).
  String get androidEnginePath {
    switch (this) {
      case Arch.arm32:
        return 'android_release';
      case Arch.arm64:
        return 'android_release_arm64';
      case Arch.x86_64:
        return 'android_release_x64';
    }
  }

  static Iterable<Arch> get availableAndroidArchs {
    if (engineConfig.localEngine != null) {
      final localEngineOutName = engineConfig.localEngine!;
      final arch = Arch.values.firstWhereOrNull(
        (element) => localEngineOutName == element.androidEnginePath,
      );
      if (arch == null) {
        throw Exception(
          'Unknown local engine architecture for '
          '--local-engine=$localEngineOutName\n'
          'Known values: '
          '${Arch.values.map((e) => e.androidEnginePath)}',
        );
      }

      return [arch];
    }
    return Arch.values;
  }
}

extension TargetPlatformArgs on Iterable<Arch> {
  /// The value to pass to the --target-platforms flag.
  String get targetPlatformArg => map((e) => e.targetPlatformCliArg).join(',');
}
