import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Open, () {
    late Open open;
    late ShorebirdProcess process;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      process = MockShorebirdProcess();
      open = Open();
    });

    group('newApplication', () {
      late Directory workingDirectory;

      setUp(() {
        workingDirectory = Directory.systemTemp.createTempSync();
        File(p.join(workingDirectory.path, 'Contents', 'MacOS', 'test'))
            .createSync(recursive: true);
      });

      test('executes correct command and streams logs', () async {
        final openProcess = MockProcess();
        final logProcess = MockProcess();

        when(() => process.start('open', any())).thenAnswer((_) async {
          return openProcess;
        });
        when(() => process.start('log', any())).thenAnswer((_) async {
          return logProcess;
        });

        when(() => logProcess.stdout).thenAnswer(
          (_) => Stream.fromIterable([utf8.encode('hello world') as List<int>]),
        );

        final stream = await runWithOverrides(
          () => open.newApplication(path: workingDirectory.path),
        );

        expect(stream, emits(utf8.encode('hello world')));
        verify(() => process.start('open', ['-n', workingDirectory.path]));
        verify(
          () => process.start(
            'log',
            ['stream', '--style=compact', '--process', 'test'],
          ),
        ).called(1);
      });
    });
  });
}
