import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'app.g.dart';

/// {@template app}
/// A single app which contains zero or more releases.
/// {@endtemplate}
@JsonSerializable()
class App {
  /// {@macro app}
  App({required this.productId, List<Release>? releases})
      : releases = releases ?? [];

  /// Converts a Map<String, dynamic> to an [App]
  factory App.fromJson(Map<String, dynamic> json) => _$AppFromJson(json);

  /// Converts a [App] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$AppToJson(this);

  /// The product ID of the app.
  final String productId;

  /// List of releases associated with this app.
  final List<Release> releases;
}
