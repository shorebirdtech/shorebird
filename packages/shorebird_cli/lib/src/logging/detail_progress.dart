import 'package:mason_logger/mason_logger.dart';

/// {@template detail_progress}
/// A [Progress] wrapper that allows for maintaining a base message (e.g., a
/// task title) while updating the message with more specific information,
/// rendered in dark gray.
/// {@endtemplate}
class DetailProgress implements Progress {
  /// {@macro detail_progress}
  DetailProgress._({
    required Progress progress,
    required String primaryMessage,
  })  : _progress = progress,
        _primaryMessage = primaryMessage;

  String _primaryMessage;
  String? _detailMessage;
  final Progress _progress;

  /// Updates the main message of the progress with the given [message]. This is
  /// roughly equivalent to calling [Progress.update], except that this will
  /// preserve the detail message if one exists.
  void updatePrimaryMessage(String message) {
    _primaryMessage = message;
    _updateImpl();
  }

  /// Updates the detail message of the progress with the given [message].
  void updateDetailMessage(String? message) {
    _detailMessage = message;
    _updateImpl();
  }

  @override
  void update(String update) {
    _primaryMessage = update;
    _detailMessage = null;
    _updateImpl();
  }

  void _updateImpl() {
    final detailMessage = _detailMessage;
    if (detailMessage != null) {
      _progress.update('$_primaryMessage ${darkGray.wrap(detailMessage)}');
    } else {
      _progress.update(_primaryMessage);
    }
  }

  @override
  void cancel() {
    _progress.cancel();
  }

  @override
  void complete([String? update]) {
    _progress.complete(update ?? _primaryMessage);
  }

  @override
  void fail([String? update]) {
    _progress.fail(update ?? _primaryMessage);
  }
}

/// {@template detail_progress_logger}
/// Adds a method to [Logger] to create an [DetailProgress] instance.
/// {@endtemplate}
extension DetailProgressLogger on Logger {
  /// {@macro detail_progress_logger}
  DetailProgress detailProgress(String primaryMessage) {
    return DetailProgress._(
      progress: progress(primaryMessage),
      primaryMessage: primaryMessage,
    );
  }
}
