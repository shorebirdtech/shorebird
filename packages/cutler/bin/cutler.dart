import 'package:cutler/cutler.dart';
import 'package:cutler/logger.dart';
import 'package:scoped/scoped.dart';

void main(List<String> args) {
  runScoped(
    () => Cutler().run(args),
    values: {
      loggerRef,
    },
  );
}
