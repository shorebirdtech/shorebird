import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_summary.dart';

/// {@template get_zap_previews_response}
/// The response body for GET /zap/previews.
/// {@endtemplate}
@immutable
class GetZapPreviewsResponse {
  /// {@macro get_zap_previews_response}
  const GetZapPreviewsResponse({
    required this.previews,
    @deprecated required this.channels,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetZapPreviewsResponse].
  factory GetZapPreviewsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetZapPreviewsResponse',
      json,
      () => GetZapPreviewsResponse(
        previews: (json['previews'] as List)
            .map<ZapPreviewSummary>(
              (e) => ZapPreviewSummary.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        channels: (json['channels'] as List)
            .map<ZapPreviewSummary>(
              (e) => ZapPreviewSummary.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetZapPreviewsResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetZapPreviewsResponse.fromJson(json);
  }

  /// The previews on this page, most recently updated first.
  final List<ZapPreviewSummary> previews;

  /// The same list as `previews`, under the name older Zap containers read.
  @deprecated
  final List<ZapPreviewSummary> channels;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page. Absent on the last page.
  final String? nextCursor;

  /// Converts a [GetZapPreviewsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'previews': previews.map((e) => e.toJson()).toList(),
      'channels': channels.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(previews),
    listHash(channels),
    nextCursor,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetZapPreviewsResponse &&
        listsEqual(previews, other.previews) &&
        listsEqual(channels, other.channels) &&
        nextCursor == other.nextCursor;
  }
}
