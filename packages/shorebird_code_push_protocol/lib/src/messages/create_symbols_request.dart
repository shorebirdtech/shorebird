import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
import 'package:shorebird_code_push_protocol/src/models/symbols_compression.dart';
import 'package:shorebird_code_push_protocol/src/models/symbols_format.dart';

/// {@template create_symbols_request}
/// Metadata for one architecture's symbol file. POST to
/// /apps/{appId}/releases/{releaseId}/symbols or
/// /apps/{appId}/patches/{patchId}/symbols and PUT the compressed bytes
/// to the session URI that comes back.
/// {@endtemplate}
@immutable
class CreateSymbolsRequest {
  /// {@macro create_symbols_request}
  const CreateSymbolsRequest({
    required this.platform,
    required this.arch,
    required this.format,
    required this.compression,
    required this.size,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateSymbolsRequest].
  factory CreateSymbolsRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateSymbolsRequest',
      json,
      () => CreateSymbolsRequest(
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        arch: json['arch'] as String,
        format: SymbolsFormat.fromJson(json['format'] as String),
        compression: SymbolsCompression.fromJson(json['compression'] as String),
        size: json['size'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateSymbolsRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateSymbolsRequest.fromJson(json);
  }

  /// The platform the symbols are for.
  final ReleasePlatform platform;

  /// The arch the symbols are for.
  final String arch;

  /// Which symbol file this is.
  final SymbolsFormat format;

  /// What the bytes are compressed with.
  final SymbolsCompression compression;

  /// The size of the compressed file in bytes.
  final int size;

  /// Converts a [CreateSymbolsRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'platform': platform.toJson(),
      'arch': arch,
      'format': format.toJson(),
      'compression': compression.toJson(),
      'size': size,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    platform,
    arch,
    format,
    compression,
    size,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateSymbolsRequest &&
        platform == other.platform &&
        arch == other.arch &&
        format == other.format &&
        compression == other.compression &&
        size == other.size;
  }
}
