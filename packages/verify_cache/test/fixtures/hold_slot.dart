// Holds a RunSlot from its own process, since a lock never excludes the
// process that holds it. Prints `held` once it has a slot, then holds it
// until killed.
import 'dart:async';
import 'dart:io';

import 'package:verify_cache/verify_cache.dart';

Future<void> main(List<String> args) async {
  await RunSlot.acquire(Directory(args[0]), int.parse(args[1]));
  stdout.writeln('held');
  await stdout.flush();
  // A pending timer, unlike a future nothing completes, keeps the VM alive.
  Timer(const Duration(days: 1), () {});
}
