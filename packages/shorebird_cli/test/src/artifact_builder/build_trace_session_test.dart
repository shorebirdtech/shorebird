import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_session.dart';
import 'package:test/test.dart';

void main() {
  group(BuildTraceSession, () {
    test('holds commandStartedAt', () {
      final started = DateTime.utc(2026, 4, 17, 12, 30);
      final session = BuildTraceSession(commandStartedAt: started);
      expect(session.commandStartedAt, started);
    });
  });

  group('buildTraceSessionRef', () {
    test('default factory produces a session with a recent start time', () {
      final before = DateTime.now();
      final session = runScoped(
        () => buildTraceSession,
        values: {buildTraceSessionRef},
      );
      final after = DateTime.now();

      expect(session, isA<BuildTraceSession>());
      expect(
        session.commandStartedAt.isAfter(
          before.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        session.commandStartedAt.isBefore(
          after.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('overrideWith replaces the default session', () {
      final fixed = DateTime.utc(2020);
      final session = runScoped(
        () => buildTraceSession,
        values: {
          buildTraceSessionRef.overrideWith(
            () => BuildTraceSession(commandStartedAt: fixed),
          ),
        },
      );
      expect(session.commandStartedAt, fixed);
    });
  });
}
