import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// The different types of shorebird releases that can be created.
enum ReleaseType {
  /// An Android archive used in a hybrid app.
  aar,

  /// A full Flutter Android app.
  android,

  /// A full Flutter iOS app.
  ios,

  /// A full Flutter Linux app.
  linux,

  /// A full Flutter macOS app.
  macos,

  /// An iOS framework used in a hybrid app.
  iosFramework,

  /// A full Flutter Windows app.
  windows;

  /// The CLI argument used to specify the release type(s).
  String get cliName {
    switch (this) {
      case ReleaseType.aar:
        return 'aar';
      case ReleaseType.android:
        return 'android';
      case ReleaseType.ios:
        return 'ios';
      case ReleaseType.iosFramework:
        return 'ios-framework';
      case ReleaseType.linux:
        return 'linux';
      case ReleaseType.macos:
        return 'macos';
      case ReleaseType.windows:
        return 'windows';
    }
  }

  /// The platform associated with the release type.
  ReleasePlatform get releasePlatform {
    switch (this) {
      case ReleaseType.aar:
        return ReleasePlatform.android;
      case ReleaseType.android:
        return ReleasePlatform.android;
      case ReleaseType.ios:
        return ReleasePlatform.ios;
      case ReleaseType.iosFramework:
        return ReleasePlatform.ios;
      case ReleaseType.linux:
        return ReleasePlatform.linux;
      case ReleaseType.macos:
        return ReleasePlatform.macos;
      case ReleaseType.windows:
        return ReleasePlatform.windows;
    }
  }

  /// The server-side arch of this release type's primary release artifact,
  /// the one patches are built against.
  String get primaryArtifactArch => switch (this) {
    ReleaseType.aar => 'aar',
    ReleaseType.android => 'aab',
    ReleaseType.ios => 'xcarchive',
    ReleaseType.iosFramework => 'xcframework',
    // A zipped copy of `build/linux/x64/release/bundle`, as produced by
    // `flutter build linux --release`. At its top level it contains data/
    // (flutter assets), lib/ (libapp.so and libflutter_linux_gtk.so) and the
    // executable.
    ReleaseType.linux => 'bundle',
    ReleaseType.macos => 'app',
    // A zipped copy of `build/windows/x64/runner/Release`, as produced by
    // `flutter build windows --release`. At its top level it contains
    // flutter.dll, the app's .exe and data/ (flutter assets and app.so).
    ReleaseType.windows => 'win_archive',
  };

  /// The server-side arch of this release type's supplement artifact, which
  /// holds build outputs (such as obfuscation maps) that patches need.
  String get supplementArtifactArch => switch (this) {
    ReleaseType.aar => 'aar_supplement',
    ReleaseType.android => 'android_supplement',
    ReleaseType.ios => 'ios_supplement',
    ReleaseType.iosFramework => 'ios_framework_supplement',
    ReleaseType.linux => 'linux_supplement',
    ReleaseType.macos => 'macos_supplement',
    ReleaseType.windows => 'windows_supplement',
  };
}

/// Extension on [ArgResults] to get the release types from the CLI arguments.
extension ReleaseTypeArgs on ArgResults {
  /// The release types specified in the CLI arguments.
  Iterable<ReleaseType> get releaseTypes {
    List<String>? releaseTypeCliNames;
    if (wasParsed('platforms')) {
      releaseTypeCliNames = this['platforms'] as List<String>;
    } else {
      if (arguments.isNotEmpty) {
        final platformCliName = arguments.first;
        if (ReleaseType.values.none(
          (target) => target.cliName == platformCliName,
        )) {
          throw ArgumentError('Invalid platform: $platformCliName');
        }
        releaseTypeCliNames = [platformCliName];
      }
    }

    return releaseTypeCliNames?.map(
          (cliName) => ReleaseType.values.firstWhere(
            (target) => target.cliName == cliName,
          ),
        ) ??
        const [];
  }
}
