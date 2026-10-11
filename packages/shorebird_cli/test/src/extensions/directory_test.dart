import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group('TemporaryDirectory', () {
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    setUp(() {
      logger = MockShorebirdLogger();
    });

    group('deleteTemporarySync', () {
      test('deletes the directory and its contents', () {
        final directory = Directory.systemTemp.createTempSync();
        File(
          p.join(directory.path, 'nested', 'file'),
        ).createSync(recursive: true);

        runWithOverrides(directory.deleteTemporarySync);

        expect(directory.existsSync(), isFalse);
      });

      test('does nothing when the directory does not exist', () {
        final directory = Directory(
          p.join(Directory.systemTemp.path, 'shorebird-does-not-exist'),
        );

        expect(
          () => runWithOverrides(directory.deleteTemporarySync),
          returnsNormally,
        );
      });

      test(
        'logs instead of throwing when the directory cannot be deleted',
        () {
          final parent = Directory.systemTemp.createTempSync();
          final directory = Directory(p.join(parent.path, 'locked'))
            ..createSync();
          File(p.join(directory.path, 'file')).createSync();
          // Without write permission on the parent, the directory can't be
          // removed from it.
          Process.runSync('chmod', ['555', parent.path]);
          addTearDown(() {
            Process.runSync('chmod', ['755', parent.path]);
            parent.deleteSync(recursive: true);
          });

          expect(
            () => runWithOverrides(directory.deleteTemporarySync),
            returnsNormally,
          );
          verify(
            () => logger.detail(
              any(that: startsWith('Failed to delete ${directory.path}')),
            ),
          ).called(1);
        },
        skip: p.style == p.Style.windows
            ? 'chmod is not available on Windows'
            : null,
      );
    });
  });
}
