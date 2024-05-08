import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [Logger] instance.
final loggerRef = create(ShorebirdLogger.new);

/// The [Logger] instance available in the current zone.
ShorebirdLogger get logger => read(loggerRef);

class ShorebirdLogger extends Logger {
  static const _logFileName = 'shorebird.log';

  late final File logFile = (() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final file = File(
      p.join(
        shorebirdEnv.shorebirdRoot.path,
        'logs',
        '${timestamp}_$_logFileName',
      ),
    );

    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }

    return file;
  })();

  void _logToFile(String level, String message, {required LogStyle style}) {
    final styledMessage = style(message);

    logFile.writeAsStringSync(
      '${DateTime.now().toIso8601String()} [$level] $styledMessage\n',
      mode: FileMode.append,
    );
  }

  @override
  void info(String? message, {LogStyle? style}) {
    super.info(message, style: style);
    _logToFile(
      'INFO',
      message ?? '',
      style: style ?? theme.info,
    );
  }

  @override
  void detail(String? message, {LogStyle? style}) {
    super.detail(message, style: style);
    _logToFile(
      'DETAIL',
      message ?? '',
      style: style ?? theme.detail,
    );
  }

  @override
  void warn(String? message, {String tag = 'WARN', LogStyle? style}) {
    super.warn(message, tag: tag, style: style);
    _logToFile(
      'WARN',
      message ?? '',
      style: style ?? theme.warn,
    );
  }

  @override
  void success(String? message, {LogStyle? style}) {
    super.success(message, style: style);
    _logToFile(
      'SUCCESS',
      message ?? '',
      style: style ?? theme.success,
    );
  }

  @override
  void alert(String? message, {LogStyle? style}) {
    super.alert(message, style: style);
    _logToFile(
      'ALERT',
      message ?? '',
      style: style ?? theme.alert,
    );
  }

  @override
  void err(String? message, {LogStyle? style}) {
    super.err(message, style: style);
    _logToFile(
      'ERROR',
      message ?? '',
      style: style ?? theme.err,
    );
  }
}
