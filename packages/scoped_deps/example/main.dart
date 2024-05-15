// ignore_for_file: avoid_print
import 'package:scoped_deps/scoped_deps.dart';

final value = create(() => 42);

void main() {
  runScoped(scopeA, values: {value});
}

void scopeA() {
  print(read(value)); // 42
  runScoped(scopeB, values: {value.overrideWith(() => 0)});
}

void scopeB() {
  print(read(value)); // 0
}
