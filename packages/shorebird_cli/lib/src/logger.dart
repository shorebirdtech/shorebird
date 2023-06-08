import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';

// A reference to a [Logger] instance.
ScopedRef<Logger> loggerRef = create(Logger.new);

// The [Logger] instance available in the current zone.
Logger get logger => read(loggerRef);
