import 'package:shorebird_build_trace/shorebird_build_trace.dart';
import 'package:test/test.dart';

void main() {
  group('TraceCategory.parse', () {
    test('parses each non-fallback wire value to its enum', () {
      for (final c in TraceCategory.values) {
        if (c == TraceCategory.unknown) continue;
        expect(
          TraceCategory.parse(c.wireName),
          c,
          reason: 'wireName "${c.wireName}" should parse to $c',
        );
      }
    });

    test('returns unknown for null', () {
      expect(TraceCategory.parse(null), TraceCategory.unknown);
    });

    test('returns unknown for an unrecognized wire value', () {
      expect(TraceCategory.parse('brand-new-category'), TraceCategory.unknown);
    });

    test('returns unknown for empty string (not the unknown wireName)', () {
      // unknown.wireName is '' but the parse loop skips unknown, so empty
      // string falls through to the fallback return.
      expect(TraceCategory.parse(''), TraceCategory.unknown);
    });
  });

  group('GradleTaskKind.parse', () {
    test(
      'parses each wire value to its enum (including the "other" literal)',
      () {
        for (final k in GradleTaskKind.values) {
          expect(
            GradleTaskKind.parse(k.wireName),
            k,
            reason: 'wireName "${k.wireName}" should parse to $k',
          );
        }
      },
    );

    test('returns other for null', () {
      expect(GradleTaskKind.parse(null), GradleTaskKind.other);
    });

    test('returns other for an unrecognized wire value', () {
      expect(
        GradleTaskKind.parse('brand-new-kind'),
        GradleTaskKind.other,
      );
    });
  });

  group('PodInstallPhase.parse', () {
    test('parses each non-fallback wire value to its enum', () {
      for (final p in PodInstallPhase.values) {
        if (p == PodInstallPhase.other) continue;
        expect(
          PodInstallPhase.parse(p.wireName),
          p,
          reason: 'wireName "${p.wireName}" should parse to $p',
        );
      }
    });

    test('returns other for null', () {
      expect(PodInstallPhase.parse(null), PodInstallPhase.other);
    });

    test('returns other for an unrecognized wire value', () {
      expect(
        PodInstallPhase.parse('brand-new-phase'),
        PodInstallPhase.other,
      );
    });

    test('returns other for empty string (not the other wireName)', () {
      // other.wireName is '' but the parse loop skips other, so empty
      // string falls through to the fallback return.
      expect(PodInstallPhase.parse(''), PodInstallPhase.other);
    });
  });
}
