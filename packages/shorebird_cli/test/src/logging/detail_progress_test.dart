import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(DetailProgress, () {
    late ShorebirdLogger logger;
    late Progress progress;
    late DetailProgress detailProgress;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    setUp(() {
      logger = MockShorebirdLogger();
      progress = MockProgress();

      when(() => logger.progress(any())).thenReturn(progress);

      detailProgress = runWithOverrides(() => logger.detailProgress('title'));
    });

    group('updatePrimaryMessage', () {
      group('when no detail message is set', () {
        test('updates the primary message', () {
          detailProgress.updatePrimaryMessage('new title');
          verify(() => progress.update('new title')).called(1);
        });
      });

      group('when a detail message is present', () {
        setUp(() {
          detailProgress.updateDetailMessage('detail');
        });

        test('updates the primary message and detail message', () {
          detailProgress.updatePrimaryMessage('new title');
          verify(
            () => progress.update('new title ${darkGray.wrap('detail')}'),
          ).called(1);
        });
      });
    });

    group('updateDetailMessage', () {
      test('updates the detail message', () {
        detailProgress.updateDetailMessage('new detail');
        verify(
          () => progress.update('title ${darkGray.wrap('new detail')}'),
        ).called(1);
      });

      test('can unset the detail message', () {
        detailProgress.updateDetailMessage(null);
        verify(() => progress.update('title')).called(1);
      });
    });

    group('update', () {
      test('updates the primary message', () {
        detailProgress.update('new title');
        verify(() => progress.update('new title')).called(1);
      });

      group('when a detail message is set', () {
        setUp(() {
          detailProgress.updateDetailMessage('detail');
        });

        test('unsets the detail message', () {
          detailProgress.update('new title');
          verify(() => progress.update('new title')).called(1);
        });
      });
    });

    group('cancel', () {
      test('cancels the progress', () {
        detailProgress.cancel();
        verify(() => progress.cancel()).called(1);
      });
    });

    group('complete', () {
      test('completes the progress', () {
        detailProgress.complete();
        verify(() => progress.complete('title')).called(1);
      });

      test('completes the progress with an update', () {
        detailProgress.complete('update');
        verify(() => progress.complete('update')).called(1);
      });
    });

    group('fail', () {
      test('fails the progress', () {
        detailProgress.fail();
        verify(() => progress.fail('title')).called(1);
      });

      test('fails the progress with an update', () {
        detailProgress.fail('update');
        verify(() => progress.fail('update')).called(1);
      });
    });

    test('implements Progress', () {
      expect(detailProgress, isA<Progress>());
    });
  });
}
