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
        pid: 42,
        threadId: 1,
        args: {'method': 'POST'},
      );

      expect(event.toJson(), {
        'name': 'POST api.shorebird.dev',
        'cat': 'network',
        'ph': 'X',
        'ts': 100,
        'dur': 250,
        'pid': 42,
        'tid': 1,
        'args': {'method': 'POST'},
      });
    });

    test('toJson omits args when null', () {
      final event = ShorebirdTraceEvent(
        name: 'x',
        category: 'shorebird',
        startMicros: 0,
        durationMicros: 1,
        pid: 1,
      );
      expect(event.toJson().containsKey('args'), isFalse);
    });

    test('threadId defaults to 2 and is overridable', () {
      final defaultTid = ShorebirdTraceEvent(
        name: 'x',
        category: 'c',
        startMicros: 0,
        durationMicros: 1,
        pid: 1,
      );
      expect(defaultTid.threadId, 2);

      final customTid = ShorebirdTraceEvent(
        name: 'x',
        category: 'c',
        startMicros: 0,
        durationMicros: 1,
        pid: 1,
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
          pid: 1,
        ),
      );
      expect(tracer.events, hasLength(1));
    });

    test('events is unmodifiable', () {
      expect(
        () => tracer.events.add(<String, Object?>{'foo': 'bar'}),
        throwsUnsupportedError,
      );
    });

    test('addNetworkEvent tags span with network category and tid=1', () {
      tracer.addNetworkEvent(
        name: 'GET api.shorebird.dev',
        startMicros: 0,
        durationMicros: 1,
      );
      expect(tracer.events, hasLength(1));
      expect(tracer.events.single['cat'], 'network');
      expect(tracer.events.single['tid'], 1);
      expect(tracer.events.single['pid'], isA<int>());
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
      expect(event['name'], 'unit-test');
      expect(event['cat'], 'shorebird');
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
      expect(tracer.events.single['name'], 'unit-test');
    });

    test('span forwards args', () async {
      await tracer.span<void>(
        name: 'x',
        category: 'c',
        args: {'k': 'v'},
        body: () async {},
      );
      expect(tracer.events.single['args'], {'k': 'v'});
    });

    test('addSpawnFlowStart emits ph:s flow event', () {
      tracer.addSpawnFlowStart(id: 4242, atMicros: 1000);
      final event = tracer.events.single;
      expect(event['ph'], 's');
      expect(event['id'], 4242);
      expect(event['ts'], 1000);
      expect(event['bp'], 'e');
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

      test(
        'appends events + process/thread metadata to an existing trace',
        () {
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
          tracer.addNetworkEvent(
            name: 'POST api.shorebird.dev',
            startMicros: 200,
            durationMicros: 50,
          );

          tracer.mergeInto(traceFile);

          final decoded = jsonDecode(traceFile.readAsStringSync()) as List;
          // 1 pre-existing flutter span + 3 metadata (process_name +
          // 2 thread_name) + 1 network span.
          expect(decoded, hasLength(5));
          expect((decoded[0] as Map)['name'], 'flutter build');
          // Metadata events order: process_name, thread_name(network),
          // thread_name(shorebird_cli).
          expect((decoded[1] as Map)['name'], 'process_name');
          expect((decoded[2] as Map)['name'], 'thread_name');
          expect((decoded[3] as Map)['name'], 'thread_name');
          expect((decoded[4] as Map)['name'], 'POST api.shorebird.dev');
        },
      );

      test('no-op when the trace file does not exist', () {
        tracer.addNetworkEvent(
          name: 'x',
          startMicros: 0,
          durationMicros: 1,
        );
        tracer.mergeInto(traceFile);
        expect(traceFile.existsSync(), isFalse);
      });

      test('no-op when existing file is not a JSON array', () {
        traceFile.writeAsStringSync('{"not":"an array"}');
        tracer.addNetworkEvent(
          name: 'x',
          startMicros: 0,
          durationMicros: 1,
        );
        tracer.mergeInto(traceFile);
        expect(traceFile.readAsStringSync(), '{"not":"an array"}');
      });

      test('no-op when existing file is malformed JSON', () {
        traceFile.writeAsStringSync('not json');
        tracer.addNetworkEvent(
          name: 'x',
          startMicros: 0,
          durationMicros: 1,
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

  group('currentProcessId', () {
    test('returns a positive int and is stable within a process', () {
      final first = currentProcessId();
      expect(first, greaterThan(0));
      expect(currentProcessId(), first);
    });
  });
}
