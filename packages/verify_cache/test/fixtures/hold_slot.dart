// Holds a RunSlot from its own process, since a lock never excludes the
// process that holds it. Prints `held` once it has a slot, then holds it
// until killed.
//
// A third argument prints `retry` per try and drops the wait between tries,
// so a test can count tries instead of spending a second on each.
import 'dart:async';
import 'dart:io';

import 'package:verify_cache/verify_cache.dart';

Future<void> main(List<String> args) async {
  final traceRetries = args.length > 2;
  await RunSlot.acquire(
    Directory(args[0]),
    int.parse(args[1]),
    // Written without a flush, which binds stdout: the write on the next try
    // would throw while that flush is still pending.
    onWait: () => stdout.writeln('waiting'),
    sleep: traceRetries
        ? (_) async => stdout.writeln('retry')
        : Future<void>.delayed,
  );
  stdout.writeln('held');
  await stdout.flush();
  // A pending timer, unlike a future nothing completes, keeps the VM alive.
  Timer(const Duration(days: 1), () {});
}
