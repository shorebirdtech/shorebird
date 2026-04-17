import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdTraceEvent, () {
    test('toJson emits a Chrome Trace Event Format complete event', () {
      final event = ShorebirdTraceEvent(
        name: 'POST api.shorebird.dev',
        category: 'network',
        startMicros: 100,
        durationMicros: 250,
        args: {'method': 'POST'},
      );

      expect(event.toJson(), {
        'name': 'POST api.shorebird.dev',
        'cat': 'network',
        'ph': 'X',
        'ts': 100,
        'dur': 250,
        'pid': 1,
        'tid': 5,
        'args': {'method': 'POST'},
      });
    });

    test('toJson omits args when null', () {
      final event = ShorebirdTraceEvent(
        name: 'x',
        category: 'shorebird',
        startMicros: 0,
        durationMicros: 1,
      );
      expect(event.toJson().containsKey('args'), isFalse);
    });

    test('threadId defaults to 5 and is overridable', () {
      final defaultTid = ShorebirdTraceEvent(
        name: 'x',
        category: 'c',
        startMicros: 0,
        durationMicros: 1,
      );
      expect(defaultTid.threadId, 5);

      final customTid = ShorebirdTraceEvent(
        name: 'x',
        category: 'c',
        startMicros: 0,
        durationMicros: 1,
        threadId: 42,
      );
      expect(customTid.threadId, 42);
    });
  });

  group(ShorebirdTracer, () {
    late ShorebirdTracer tracer;

    setUp(() {
      tracer = ShorebirdTracer();
    });

    test('addEvent appends to events', () {
      expect(tracer.events, isEmpty);
      tracer.addEvent(
        ShorebirdTraceEvent(
          name: 'x',
          category: 'c',
          startMicros: 0,
          durationMicros: 1,
        ),
      );
      expect(tracer.events, hasLength(1));
    });

    test('events is unmodifiable', () {
      expect(
        () => tracer.events.add(
          ShorebirdTraceEvent(
            name: 'x',
            category: 'c',
            startMicros: 0,
            durationMicros: 1,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('span records an event for a successful body', () async {
      final result = await tracer.span<int>(
        name: 'unit-test',
        category: 'shorebird',
        body: () async => 42,
      );
      expect(result, 42);
      expect(tracer.events, hasLength(1));
      final event = tracer.events.single;
      expect(event.name, 'unit-test');
      expect(event.category, 'shorebird');
    });

    test('span records an event even when body throws', () async {
      await expectLater(
        tracer.span<int>(
          name: 'unit-test',
          category: 'shorebird',
          body: () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(tracer.events, hasLength(1));
      expect(tracer.events.single.name, 'unit-test');
    });

    test('span forwards threadId and args', () async {
      await tracer.span<void>(
        name: 'x',
        category: 'c',
        threadId: 9,
        args: {'k': 'v'},
        body: () async {},
      );
      expect(tracer.events.single.threadId, 9);
      expect(tracer.events.single.args, {'k': 'v'});
    });

    group('mergeInto', () {
      late Directory tempDir;
      late File traceFile;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('shorebird_tracer_test_');
        traceFile = File('${tempDir.path}/trace.json');
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('appends events to an existing Flutter-written trace array', () {
        traceFile.writeAsStringSync(
          jsonEncode([
            {
              'ph': 'X',
              'name': 'flutter build',
              'cat': 'flutter',
              'ts': 0,
              'dur': 100,
              'pid': 1,
              'tid': 1,
            },
          ]),
        );
        tracer.addEvent(
          ShorebirdTraceEvent(
            name: 'POST api.shorebird.dev',
            category: 'network',
            startMicros: 200,
            durationMicros: 50,
          ),
        );

        tracer.mergeInto(traceFile);

        final decoded = jsonDecode(traceFile.readAsStringSync()) as List;
        expect(decoded, hasLength(2));
        expect((decoded[0] as Map)['name'], 'flutter build');
        expect((decoded[1] as Map)['name'], 'POST api.shorebird.dev');
      });

      test('no-op when the trace file does not exist', () {
        tracer.addEvent(
          ShorebirdTraceEvent(
            name: 'x',
            category: 'c',
            startMicros: 0,
            durationMicros: 1,
          ),
        );
        tracer.mergeInto(traceFile);
        expect(traceFile.existsSync(), isFalse);
      });

      test('no-op when existing file is not a JSON array', () {
        traceFile.writeAsStringSync('{"not":"an array"}');
        tracer.addEvent(
          ShorebirdTraceEvent(
            name: 'x',
            category: 'c',
            startMicros: 0,
            durationMicros: 1,
          ),
        );
        tracer.mergeInto(traceFile);
        expect(traceFile.readAsStringSync(), '{"not":"an array"}');
      });

      test('no-op when existing file is malformed JSON', () {
        traceFile.writeAsStringSync('not json');
        tracer.addEvent(
          ShorebirdTraceEvent(
            name: 'x',
            category: 'c',
            startMicros: 0,
            durationMicros: 1,
          ),
        );
        tracer.mergeInto(traceFile);
        expect(traceFile.readAsStringSync(), 'not json');
      });
    });
  });

  group('shorebirdTracerRef', () {
    test('resolves to a ShorebirdTracer inside a scope', () {
      final tracer = runScoped(
        () => shorebirdTracer,
        values: {shorebirdTracerRef},
      );
      expect(tracer, isA<ShorebirdTracer>());
    });
  });
}
