import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Line hit counts per source file, read from one or more lcov tracefiles.
///
/// Records for the same source file are merged by summing each line's hits,
/// so tracefiles from test shards that instrument the same sources combine
/// into one total instead of counting each line once per shard.
class LcovReport {
  LcovReport._(this._hitsByFile);

  /// Parses and merges [tracefiles], each the text of an lcov tracefile.
  ///
  /// Only `SF:` and `DA:` records are read; `LF:`/`LH:` totals are derived
  /// from `DA:`, so a tracefile whose totals disagree with its lines is
  /// counted by its lines.
  factory LcovReport.parse(Iterable<String> tracefiles) {
    final hitsByFile = <String, Map<int, int>>{};
    for (final tracefile in tracefiles) {
      Map<int, int>? current;
      for (final raw in tracefile.split('\n')) {
        final line = raw.trim();
        if (line.startsWith('SF:')) {
          current = hitsByFile.putIfAbsent(line.substring(3), () => {});
        } else if (line.startsWith('DA:') && current != null) {
          final fields = line.substring(3).split(',');
          if (fields.length < 2) {
            throw FormatException('Malformed lcov line', line);
          }
          final number = int.parse(fields[0]);
          final hits = int.parse(fields[1]);
          current[number] = (current[number] ?? 0) + hits;
        } else if (line == 'end_of_record') {
          current = null;
        }
      }
    }
    return LcovReport._(hitsByFile);
  }

  final Map<String, Map<int, int>> _hitsByFile;

  /// Source files in the report, in the order first seen.
  Iterable<String> get files => _hitsByFile.keys;

  /// A report without the files matching any of [globs].
  ///
  /// Globs match the path as the tracefile wrote it, with `/` separators.
  /// Paths are resolved against `/`, so `**/*.g.dart` matches both
  /// `lib/a.g.dart` and `/home/runner/work/x/lib/a.g.dart`, while
  /// `lib/**/*.g.dart` matches only paths starting with `lib/`.
  LcovReport exclude(Iterable<String> globs) {
    // Resolving against '/' lets one glob match both absolute paths (Dart's
    // format_coverage) and relative ones (flutter test).
    final context = p.Context(style: p.Style.posix, current: '/');
    final matchers = [for (final g in globs) Glob(g, context: context)];
    return LcovReport._({
      for (final MapEntry(key: file, value: hits) in _hitsByFile.entries)
        if (!matchers.any((m) => m.matches(file.replaceAll(r'\', '/'))))
          file: hits,
    });
  }

  /// Number of instrumented lines.
  int get linesFound =>
      _hitsByFile.values.fold(0, (sum, hits) => sum + hits.length);

  /// Number of instrumented lines run at least once.
  int get linesHit => _hitsByFile.values.fold(
    0,
    (sum, hits) => sum + hits.values.where((h) => h > 0).length,
  );

  /// Percentage of instrumented lines hit, 0 when there are none.
  double get percent => linesFound == 0 ? 0 : linesHit / linesFound * 100;

  /// Lines never hit, by file, in line order. Files fully hit are left out.
  Map<String, List<int>> get uncoveredLines => {
    for (final MapEntry(key: file, value: hits) in _hitsByFile.entries)
      if (hits.values.any((h) => h == 0))
        file: [
          for (final MapEntry(key: line, value: h) in hits.entries)
            if (h == 0) line,
        ]..sort(),
  };
}
