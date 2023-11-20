/// A function that reports download or upload progress.
typedef ProgressCallback = void Function(DataTransferProgress progress);

/// {@template data_transfer_progress}
/// Reported progress for a data upload or download.
/// {@endtemplate}
class DataTransferProgress {
  /// {@macro data_transfer_progress}
  DataTransferProgress({
    required this.bytesTransferred,
    required this.totalBytes,
    required this.url,
  });

  /// The number of bytes that have been transferred.
  final int bytesTransferred;

  /// The total number of bytes that will be transferred.
  final int totalBytes;

  /// The URL of the request.
  final Uri url;

  /// The percentage of bytes that have been transferred, between 0 and 100.
  double get progressPercentage => (bytesTransferred / totalBytes) * 100;
}
