import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template zap_preview}
/// The response body for GET /zap/previews/{previewId}: the preview's
/// current build and where to download it.
/// {@endtemplate}
@immutable
class ZapPreview {
  /// {@macro zap_preview}
  const ZapPreview({
    required this.formatVersion,
    required this.preview,
    @deprecated required this.channel,
    required this.build,
    required this.buildNumber,
    required this.name,
    required this.payloadUrl,
    @deprecated required this.payload,
    required this.payloadFormat,
    required this.payloadSize,
    required this.expiresAt,
  });

  /// Converts a `Map<String, dynamic>` to a [ZapPreview].
  factory ZapPreview.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ZapPreview',
      json,
      () => ZapPreview(
        formatVersion: json['formatVersion'] as int,
        preview: json['preview'] as String,
        channel: json['channel'] as String,
        build: json['build'] as String,
        buildNumber: json['buildNumber'] as int,
        name: json['name'] as String,
        payloadUrl: json['payloadUrl'] as String,
        payload: json['payload'] as String,
        payloadFormat: json['payloadFormat'] as String,
        payloadSize: json['payloadSize'] as int,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ZapPreview? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ZapPreview.fromJson(json);
  }

  /// The version of this response's shape. Always `1`.
  final int formatVersion;

  /// The ID of the preview.
  final String preview;

  /// The same as `preview`, under the name older Zap containers read.
  @deprecated
  final String channel;

  /// The ID of the current build.
  final String build;

  /// The current build's ordinal among the preview's published builds,
  /// starting at 1.
  final int buildNumber;

  /// The preview's display name.
  final String name;

  /// A signed URL to download the build's payload from, valid for
  /// 15 minutes.
  final String payloadUrl;

  /// The same as `payloadUrl`, under the name older Zap containers read.
  @deprecated
  final String payload;

  /// The format the payload is in, as declared when the build was started
  /// (`web-1`).
  final String payloadFormat;

  /// The payload's size in bytes.
  final int payloadSize;

  /// When the preview stops being served.
  final DateTime expiresAt;

  /// Converts a [ZapPreview] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'formatVersion': formatVersion,
      'preview': preview,
      'channel': channel,
      'build': build,
      'buildNumber': buildNumber,
      'name': name,
      'payloadUrl': payloadUrl,
      'payload': payload,
      'payloadFormat': payloadFormat,
      'payloadSize': payloadSize,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    formatVersion,
    preview,
    channel,
    build,
    buildNumber,
    name,
    payloadUrl,
    payload,
    payloadFormat,
    payloadSize,
    expiresAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZapPreview &&
        formatVersion == other.formatVersion &&
        preview == other.preview &&
        channel == other.channel &&
        build == other.build &&
        buildNumber == other.buildNumber &&
        name == other.name &&
        payloadUrl == other.payloadUrl &&
        payload == other.payload &&
        payloadFormat == other.payloadFormat &&
        payloadSize == other.payloadSize &&
        expiresAt == other.expiresAt;
  }
}
