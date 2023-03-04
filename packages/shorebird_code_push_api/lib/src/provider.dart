import 'package:shelf/shelf.dart';

extension ProvideExtension on Request {
  Request provide<T extends Object>(T Function() create) {
    return change(context: {...context, '$T': create});
  }

  T lookup<T>() {
    final value = context['$T'];
    if (value == null) {
      throw StateError(
        '''
request.lookup<$T>() called with a request that does not contain a $T.
''',
      );
    }
    return (value as T Function())();
  }
}

Middleware provider<T extends Object>(T Function(Request request) create) {
  return (handler) {
    return (req) => handler(req.provide(() => create(req)));
  };
}
