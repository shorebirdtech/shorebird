import 'dart:io' show pid;

/// The OS process id of the current Dart process.
///
/// Trivial re-export of `dart:io`'s top-level [pid] getter so call sites
/// read as "the thing that tagged this span" rather than reaching into
/// `dart:io` for one name.
int currentProcessId() => pid;
