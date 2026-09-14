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
}

/// Thrown when the positional platform arguments cannot be parsed. [message]
/// is written for the user.
class PlatformArgumentException implements Exception {
  /// Creates an exception carrying the user-facing [message].
  const PlatformArgumentException(this.message);

  /// Why the arguments were rejected, and what to do instead.
  final String message;

  @override
  String toString() => message;
}

/// The platform names accepted on the command line, sorted, for error text.
String get validPlatformNames =>
    (ReleaseType.values.map((t) => t.cliName).toList()..sort()).join(', ');

/// Extension on [ArgResults] to get the release types from the CLI arguments.
extension ReleaseTypeArgs on ArgResults {
  /// The positional arguments the user typed before any `--` separator.
  /// [rest] also contains everything after `--`, which is forwarded to
  /// Flutter and must not be validated here.
  List<String> get _ownPositionalArgs {
    final separator = arguments.indexOf('--');
    if (separator == -1) return rest;
    final forwardedCount = arguments.length - separator - 1;
    return rest.sublist(0, rest.length - forwardedCount);
  }

  /// The release types specified in the CLI arguments.
  ///
  /// Throws a [PlatformArgumentException] when the positional platform is
  /// not a valid platform, or when more than one positional argument is
  /// given.
  Iterable<ReleaseType> get releaseTypes {
    List<String>? releaseTypeCliNames;
    if (wasParsed('platforms')) {
      releaseTypeCliNames = this['platforms'] as List<String>;
    } else {
      final positionalArgs = _ownPositionalArgs;
      if (positionalArgs.isNotEmpty) {
        final platformCliName = positionalArgs.first;
        if (ReleaseType.values.none(
          (target) => target.cliName == platformCliName,
        )) {
          throw PlatformArgumentException(
            '''
Invalid platform: "$platformCliName".
Valid platforms: $validPlatformNames''',
          );
        }
        if (positionalArgs.length > 1) {
          final unexpected = positionalArgs[1];
          final String hint;
          if (RegExp(r'^\d+\.\d+').hasMatch(unexpected)) {
            hint = 'Did you mean --release-version=$unexpected?';
          } else if (ReleaseType.values.any((t) => t.cliName == unexpected)) {
            hint = 'Did you mean --platforms=$platformCliName,$unexpected?';
          } else {
            hint = 'Arguments for Flutter go after --.';
          }
          throw PlatformArgumentException(
            '''
Unexpected argument: "$unexpected".
$hint''',
          );
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
