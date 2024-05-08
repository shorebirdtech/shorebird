import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [ShorebirdLogger] instance.
final shorebirdLoggerRef = create(ShorebirdLogger.new);

/// The [ShorebirdLogger] instance available in the current zone.
ShorebirdLogger get shorebirdLogger => read(shorebirdLoggerRef);

/// {@template shorebird_logger}
/// A class that provides logging functionality for Shorebird.
/// {@endtemplate}
class ShorebirdLogger {
  /// {@macro shorebird_logger}
  ShorebirdLogger({
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final Logger _logger;

  static const _logFileName = 'shorebird.log';

  late final File _logFile = (() {
    final file = File(
      p.join(
        shorebirdEnv.shorebirdRoot.path,
        'logs',
        '${DateTime.now().toIso8601String()}_$_logFileName',
      ),
    );

    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    return file;
  })();

  void _logToFile(String level, String message, {required LogStyle style}) {
    final styledMessage = style(message);

    _logFile.writeAsStringSync(
      '${DateTime.now().toIso8601String()} [$level] $styledMessage\n',
      mode: FileMode.append,
    );
  }

  void info(String? message, {LogStyle? style}) {
    _logger.info(message, style: style);
    _logToFile(
      'INFO',
      message ?? '',
      style: style ?? _logger.theme.info,
    );
  }

  void detail(String? message, {LogStyle? style}) {
    _logger.detail(message, style: style);
    _logToFile(
      'DETAIL',
      message ?? '',
      style: style ?? _logger.theme.detail,
    );
  }

  void warn(String? message, {LogStyle? style}) {
    _logger.warn(message, style: style);
    _logToFile(
      'WARN',
      message ?? '',
      style: style ?? _logger.theme.warn,
    );
  }

  void success(String? message, {LogStyle? style}) {
    _logger.success(message, style: style);
    _logToFile(
      'SUCCESS',
      message ?? '',
      style: style ?? _logger.theme.success,
    );
  }

  void alert(String? message, {LogStyle? style}) {
    _logger.alert(message, style: style);
    _logToFile(
      'ALERT',
      message ?? '',
      style: style ?? _logger.theme.alert,
    );
  }

  void err(String? message, {LogStyle? style}) {
    _logger.err(message, style: style);
    _logToFile(
      'ERROR',
      message ?? '',
      style: style ?? _logger.theme.err,
    );
  }
}
