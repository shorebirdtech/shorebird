import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
import 'package:shorebird_code_push_protocol/src/models/release_status.dart';

/// {@template release_platform_details}
/// A release on one platform.
/// {@endtemplate}
@immutable
class ReleasePlatformDetails {
  /// {@macro release_platform_details}
  const ReleasePlatformDetails({
    required this.platform,
    required this.status,
    this.signingMode,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleasePlatformDetails].
  factory ReleasePlatformDetails.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReleasePlatformDetails',
      json,
      () => ReleasePlatformDetails(
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        status: ReleaseStatus.fromJson(json['status'] as String),
        signingMode: json['signing_mode'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReleasePlatformDetails? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReleasePlatformDetails.fromJson(json);
  }

  /// A platform to which a Shorebird release can be deployed.
  final ReleasePlatform platform;

  /// The status of a release.
  final ReleaseStatus status;

  /// How the platform's binaries are signed, one of the
  /// ReleaseSigningMode values: managed, customer or unsigned. A
  /// string rather than the enum so that a client meeting a mode
  /// added after it was built reads it as unknown instead of failing
  /// to read the release. Absent when the binaries were uploaded by a
  /// CLI from before signing was reported.
  final String? signingMode;

  /// Converts a [ReleasePlatformDetails] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'platform': platform.toJson(),
      'status': status.toJson(),
      'signing_mode': ?signingMode,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    platform,
    status,
    signingMode,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReleasePlatformDetails &&
        platform == other.platform &&
        status == other.status &&
        signingMode == other.signingMode;
  }
}
