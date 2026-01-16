import 'dart:typed_data';

import 'package:minio/minio.dart';
import 'package:self_hosted_server/src/storage/storage_provider.dart';

/// S3-compatible storage provider implementation using MinIO client.
///
/// Works with MinIO, AWS S3, DigitalOcean Spaces, and other S3-compatible
/// storage services.
class S3StorageProvider implements StorageProvider {
  /// Creates a new [S3StorageProvider].
  S3StorageProvider({
    required String endpoint,
    required int port,
    required String accessKey,
    required String secretKey,
    this.useSSL = true,
    this.region = 'us-east-1',
  }) : _minio = Minio(
          endPoint: endpoint,
          port: port,
          accessKey: accessKey,
          secretKey: secretKey,
          useSSL: useSSL,
          region: region,
        );

  final Minio _minio;

  /// Whether to use SSL for connections.
  final bool useSSL;

  /// The S3 region.
  final String region;

  @override
  Future<String> uploadArtifact({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    // Ensure bucket exists
    final bucketExists = await _minio.bucketExists(bucket);
    if (!bucketExists) {
      await _minio.makeBucket(bucket, region);
    }

    await _minio.putObject(
      bucket,
      path,
      Stream.value(Uint8List.fromList(bytes)),
      size: bytes.length,
    );
    return getPublicUrl(bucket, path);
  }

  @override
  Future<String> getSignedUploadUrl({
    required String bucket,
    required String path,
    Duration expiry = const Duration(hours: 1),
  }) async {
    return _minio.presignedPutObject(bucket, path, expires: expiry.inSeconds);
  }

  @override
  Future<String> getSignedDownloadUrl({
    required String bucket,
    required String path,
    Duration expiry = const Duration(hours: 1),
  }) async {
    return _minio.presignedGetObject(bucket, path, expires: expiry.inSeconds);
  }

  /// Get the public URL for an object.
  String getPublicUrl(String bucket, String path) {
    final protocol = useSSL ? 'https' : 'http';
    final port = _minio.port;
    return '$protocol://${_minio.endPoint}:$port/$bucket/$path';
  }

  @override
  Future<void> deleteArtifact({
    required String bucket,
    required String path,
  }) async {
    await _minio.removeObject(bucket, path);
  }

  @override
  Future<bool> artifactExists({
    required String bucket,
    required String path,
  }) async {
    try {
      await _minio.statObject(bucket, path);
      return true;
    } on MinioError {
      return false;
    }
  }

  @override
  Future<List<String>> listArtifacts({
    required String bucket,
    String? prefix,
  }) async {
    final objects = <String>[];
    await for (final result
        in _minio.listObjects(bucket, prefix: prefix ?? '')) {
      if (result.key != null) {
        objects.add(result.key!);
      }
    }
    return objects;
  }
}
