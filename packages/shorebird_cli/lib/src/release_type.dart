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

  /// An iOS framework used in a hybrid app.
  iosFramework;

  /// The CLI argument used to specify the release type(s).
  String get cliName {
    switch (this) {
      case ReleaseType.android:
        return 'android';
      case ReleaseType.ios:
        return 'ios';
      case ReleaseType.iosFramework:
        return 'ios-framework';
      case ReleaseType.aar:
        return 'aar';
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
    }
  }
}

bool _isPlatform(String platform) =>
    ReleaseType.values.any((target) => target.cliName == platform);

extension ReleaseTypeArgs on ArgResults {
  Iterable<ReleaseType> get releaseTypes {
    final List<String> releaseTypeCliNames;
    if (wasParsed('platforms')) {
      releaseTypeCliNames = this['platforms'] as List<String>;
    } else {
      final platformCliName = arguments.first;
      if (ReleaseType.values
          .none((target) => target.cliName == platformCliName)) {
        throw ArgumentError('Invalid platform: $platformCliName');
      }
      releaseTypeCliNames = [platformCliName];
    }

    return releaseTypeCliNames.map(
      (cliName) =>
          ReleaseType.values.firstWhere((target) => target.cliName == cliName),
    );
  }

  List<String> get forwardedArgs {
    if (rest.isEmpty) return [];
    if (_isPlatform(rest.first)) return rest.skip(1).toList();
    return rest;
  }
}
