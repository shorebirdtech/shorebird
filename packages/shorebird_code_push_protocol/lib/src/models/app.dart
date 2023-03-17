import 'package:json_annotation/json_annotation.dart';

part 'app.g.dart';

/// {@template app}
/// A single app which contains zero or more releases.
/// {@endtemplate}
@JsonSerializable()
class App {
  /// {@macro app}
  const App({
    required this.appId,
    this.latestReleaseVersion,
    this.latestPatchNumber,
  });

  /// Converts a Map<String, dynamic> to an [App]
  factory App.fromJson(Map<String, dynamic> json) => _$AppFromJson(json);

  /// Converts a [App] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$AppToJson(this);

  /// The ID of the app.
  final String appId;

  /// The latest release version of the app.
  final String? latestReleaseVersion;

  /// The latest patch number of the app.
  final int? latestPatchNumber;
}
