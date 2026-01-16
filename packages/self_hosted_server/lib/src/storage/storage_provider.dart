/// Abstract storage provider interface.
///
/// Implement this interface to support different storage backends
/// (S3, MinIO, GCS, local filesystem, etc.)
abstract class StorageProvider {
  /// Upload a file and return the public URL.
  Future<String> uploadArtifact({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
  });

  /// Generate a signed upload URL for direct client uploads.
  Future<String> getSignedUploadUrl({
    required String bucket,
    required String path,
    Duration expiry = const Duration(hours: 1),
  });

  /// Generate a signed download URL.
  Future<String> getSignedDownloadUrl({
    required String bucket,
    required String path,
    Duration expiry = const Duration(hours: 1),
  });

  /// Delete an artifact.
  Future<void> deleteArtifact({
    required String bucket,
    required String path,
  });

  /// Check if an artifact exists.
  Future<bool> artifactExists({
    required String bucket,
    required String path,
  });

  /// List artifacts in a path.
  Future<List<String>> listArtifacts({
    required String bucket,
    String? prefix,
  });
}
