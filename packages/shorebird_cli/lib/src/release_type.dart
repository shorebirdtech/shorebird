// ignore_for_file: public_member_api_docs

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

  /// A full Flutter macOS app.
  macos,

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
      case ReleaseType.macos:
        return 'macos';
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
      case ReleaseType.macos:
        return ReleasePlatform.macos;
      case ReleaseType.iosFramework:
        return ReleasePlatform.ios;
    }
  }
}

extension ReleaseTypeArgs on ArgResults {
  Iterable<ReleaseType> get releaseTypes {
    List<String>? releaseTypeCliNames;
    if (wasParsed('platforms')) {
      releaseTypeCliNames = this['platforms'] as List<String>;
    } else {
      if (arguments.isNotEmpty) {
        final platformCliName = arguments.first;
        if (ReleaseType.values
            .none((target) => target.cliName == platformCliName)) {
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
