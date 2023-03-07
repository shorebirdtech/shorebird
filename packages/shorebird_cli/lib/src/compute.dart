import 'dart:async';
import 'dart:isolate';

/// Perform [computation] with [input] in an [Isolate].
Future<R> compute<R, M>(FutureOr<R> Function(M) computation, M input) async {
  final resultPort = ReceivePort();
  final errorPort = ReceivePort();

  await Isolate.spawn<_IsolateConfig<M, FutureOr<R>>>(
    _spawn,
    _IsolateConfig<M, FutureOr<R>>(computation, input, resultPort.sendPort),
    onError: errorPort.sendPort,
  );

  final result = Completer<R>();
  errorPort.listen((dynamic errorData) {
    final data = errorData as List;
    final exception = Exception(data[0]);
    final stack = StackTrace.fromString(data[1] as String);
    result.completeError(exception, stack);
  });
  resultPort.listen((dynamic resultData) => result.complete(resultData as R));
  await result.future;
  resultPort.close();
  errorPort.close();
  return result.future;
}

class _IsolateConfig<M, R> {
  const _IsolateConfig(this.callback, this.message, this.resultPort);

  final R Function(M message) callback;
  final M message;
  final SendPort resultPort;

  FutureOr<R> compute() => callback(message);
}

Future<void> _spawn<R, M>(_IsolateConfig<R, FutureOr<M>> configuration) async {
  Isolate.exit(configuration.resultPort, await configuration.compute());
}
