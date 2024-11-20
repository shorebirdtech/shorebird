import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_code_push/src/generated/updater_bindings.g.dart';
import 'package:shorebird_code_push/src/shorebird_updater.dart';
import 'package:shorebird_code_push/src/shorebird_updater_io.dart';
import 'package:shorebird_code_push/src/updater.dart';
import 'package:test/test.dart';

import '../override_print.dart';

class _MockUpdater extends Mock implements Updater {}

Future<R> run<R>(
  FutureOr<R> Function() computation, {
  String? debugName,
}) async {
  return computation();
}

void main() {
  group(ShorebirdUpdaterImpl, () {
    late Updater updater;
    late ShorebirdUpdaterImpl shorebirdUpdater;

    setUpAll(() {
      registerFallbackValue(Pointer.fromAddress(0));
    });

    setUp(() {
      updater = _MockUpdater();
    });

    group('isAvailable', () {
      group('when updater is available', () {
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(1);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('returns true', () {
          expect(shorebirdUpdater.isAvailable, isTrue);
        });
      });

      group('when updater is unavailable', () {
        setUp(() {
          when(updater.currentPatchNumber).thenThrow(Exception('oops'));
        });

        test(
          'returns false',
          overridePrint((_) {
            shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
            expect(shorebirdUpdater.isAvailable, isFalse);
          }),
        );
      });
    });

    group('readPatch', () {
      group('when updater is unavailable', () {
        setUp(() {
          when(updater.currentPatchNumber).thenThrow(Exception('oops'));
        });

        test(
          'returns null',
          overridePrint((_) async {
            shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
            await expectLater(
              shorebirdUpdater.readCurrentPatch(),
              completion(isNull),
            );
            await expectLater(
              shorebirdUpdater.readNextPatch(),
              completion(isNull),
            );
          }),
        );
      });

      group('when updater has no installed patches', () {
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(0);
          when(updater.nextPatchNumber).thenReturn(0);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('returns null', () async {
          await expectLater(
            shorebirdUpdater.readCurrentPatch(),
            completion(isNull),
          );
          await expectLater(
            shorebirdUpdater.readNextPatch(),
            completion(isNull),
          );
        });
      });

      group('when updater has a downloaded patch', () {
        const currentPatchNumber = 0;
        const nextPatchNumber = 1;
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(currentPatchNumber);
          when(updater.nextPatchNumber).thenReturn(nextPatchNumber);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('returns correct patch numbers', () async {
          await expectLater(
            shorebirdUpdater.readCurrentPatch(),
            completion(isNull),
          );
          await expectLater(
            shorebirdUpdater.readNextPatch(),
            completion(
              isA<Patch>().having(
                (p) => p.number,
                'number',
                nextPatchNumber,
              ),
            ),
          );
        });
      });

      group('when updater has an installed patch', () {
        const currentPatchNumber = 1;
        const nextPatchNumber = 1;
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(currentPatchNumber);
          when(updater.nextPatchNumber).thenReturn(nextPatchNumber);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('returns correct patch numbers', () async {
          await expectLater(
            shorebirdUpdater.readCurrentPatch(),
            completion(
              isA<Patch>().having(
                (p) => p.number,
                'number',
                currentPatchNumber,
              ),
            ),
          );
          await expectLater(
            shorebirdUpdater.readNextPatch(),
            completion(
              isA<Patch>().having(
                (p) => p.number,
                'number',
                nextPatchNumber,
              ),
            ),
          );
        });
      });

      group(
          'when updater has an installed patch '
          'and a new downloaded patch', () {
        const currentPatchNumber = 1;
        const nextPatchNumber = 2;
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(currentPatchNumber);
          when(updater.nextPatchNumber).thenReturn(nextPatchNumber);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('returns correct patch numbers', () async {
          await expectLater(
            shorebirdUpdater.readCurrentPatch(),
            completion(
              isA<Patch>().having(
                (p) => p.number,
                'number',
                currentPatchNumber,
              ),
            ),
          );
          await expectLater(
            shorebirdUpdater.readNextPatch(),
            completion(
              isA<Patch>().having(
                (p) => p.number,
                'number',
                nextPatchNumber,
              ),
            ),
          );
        });
      });

      group('when an exception occurs trying to read patches', () {
        final currentPatchNumberReturnValues = [0, -1];
        setUp(() {
          when(updater.currentPatchNumber).thenAnswer((_) {
            final value = currentPatchNumberReturnValues.removeAt(0);
            if (value < 0) throw Exception('oops');
            return value;
          });
          when(updater.nextPatchNumber).thenThrow(Exception('oops'));
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('throws $ReadPatchException', () async {
          await expectLater(
            () => shorebirdUpdater.readCurrentPatch(),
            throwsA(isA<ReadPatchException>()),
          );
          await expectLater(
            () => shorebirdUpdater.readNextPatch(),
            throwsA(isA<ReadPatchException>()),
          );
        });
      });
    });

    group('checkForUpdate', () {
      group('when updater is unavailable', () {
        setUp(() {
          when(updater.currentPatchNumber).thenThrow(Exception('oops'));
        });

        test(
          'returns UpdateStatus.unavailable',
          overridePrint((_) async {
            shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
            await expectLater(
              shorebirdUpdater.checkForUpdate(),
              completion(equals(UpdateStatus.unavailable)),
            );
          }),
        );
      });

      group('when updater has an update available', () {
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(0);
          when(updater.checkForDownloadableUpdate).thenReturn(true);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('returns UpdateStatus.outdated', () async {
          await expectLater(
            shorebirdUpdater.checkForUpdate(),
            completion(equals(UpdateStatus.outdated)),
          );
        });
      });

      group('when updater has downloaded an update', () {
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(0);
          when(updater.nextPatchNumber).thenReturn(1);
          when(updater.checkForDownloadableUpdate).thenReturn(false);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('returns UpdateStatus.restartRequired', () async {
          await expectLater(
            shorebirdUpdater.checkForUpdate(),
            completion(equals(UpdateStatus.restartRequired)),
          );
        });
      });

      group('when updater installed an update and is up to date', () {
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(1);
          when(updater.nextPatchNumber).thenReturn(1);
          when(updater.checkForDownloadableUpdate).thenReturn(false);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('returns UpdateStatus.upToDate', () async {
          await expectLater(
            shorebirdUpdater.checkForUpdate(),
            completion(equals(UpdateStatus.upToDate)),
          );
        });
      });

      group('when a track is provided', () {
        const track = UpdateTrack.beta;

        setUp(() {
          when(updater.currentPatchNumber).thenReturn(0);
          when(
            () => updater.checkForDownloadableUpdate(track: track),
          ).thenReturn(true);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('forwards the provided track to the underlying updater call',
            () async {
          await expectLater(
            shorebirdUpdater.checkForUpdate(track: track),
            completion(equals(UpdateStatus.outdated)),
          );
          verify(() => updater.checkForDownloadableUpdate(track: track))
              .called(1);
        });
      });
    });

    group('update', () {
      group('when updater is unavailable', () {
        setUp(() {
          when(updater.currentPatchNumber).thenThrow(Exception('oops'));
        });

        test(
          'does nothing',
          overridePrint((_) async {
            shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
            await expectLater(shorebirdUpdater.update(), completes);
            verifyNever(updater.downloadUpdate);
          }),
        );
      });

      group('when a nullptr result is returned', () {
        setUp(() {
          when(() => updater.currentPatchNumber()).thenReturn(0);
          when(() => updater.update()).thenReturn(nullptr);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('throws $UpdateException', () async {
          await expectLater(
            shorebirdUpdater.update,
            throwsA(
              isA<UpdateException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'An unknown error occurred.',
                  )
                  .having(
                    (e) => e.reason,
                    'reason',
                    UpdateFailureReason.unknown,
                  ),
            ),
          );
          verify(updater.update).called(1);
        });
      });

      group('when no update is available', () {
        setUp(() {
          when(() => updater.currentPatchNumber()).thenReturn(0);
          final result = calloc.allocate<UpdateResult>(sizeOf<UpdateResult>());
          result.ref.status = SHOREBIRD_NO_UPDATE;
          result.ref.message = 'oops'.toNativeUtf8().cast<Char>();
          addTearDown(() {
            calloc
              ..free(result.ref.message)
              ..free(result);
          });
          when(() => updater.update()).thenReturn(result);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('throws $UpdateException', () async {
          await expectLater(
            shorebirdUpdater.update,
            throwsA(
              isA<UpdateException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'oops',
                  )
                  .having(
                    (e) => e.reason,
                    'reason',
                    UpdateFailureReason.noUpdate,
                  ),
            ),
          );
          verify(updater.update).called(1);
          verify(() => updater.freeUpdateResult(any())).called(1);
        });
      });

      group('when an error occurs during download', () {
        setUp(() {
          when(() => updater.currentPatchNumber()).thenReturn(0);
          final result = calloc.allocate<UpdateResult>(sizeOf<UpdateResult>());
          result.ref.status = SHOREBIRD_UPDATE_HAD_ERROR;
          result.ref.message = 'oops'.toNativeUtf8().cast<Char>();
          addTearDown(() {
            calloc
              ..free(result.ref.message)
              ..free(result);
          });
          when(() => updater.update()).thenReturn(result);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('throws $UpdateException', () async {
          await expectLater(
            shorebirdUpdater.update,
            throwsA(
              isA<UpdateException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'oops',
                  )
                  .having(
                    (e) => e.reason,
                    'reason',
                    UpdateFailureReason.downloadFailed,
                  ),
            ),
          );
          verify(updater.update).called(1);
          verify(() => updater.freeUpdateResult(any())).called(1);
        });
      });

      group('when the downloaded patch is bad', () {
        setUp(() {
          when(() => updater.currentPatchNumber()).thenReturn(0);
          final result = calloc.allocate<UpdateResult>(sizeOf<UpdateResult>());
          result.ref.status = SHOREBIRD_UPDATE_IS_BAD_PATCH;
          result.ref.message = 'oops'.toNativeUtf8().cast<Char>();
          addTearDown(() {
            calloc
              ..free(result.ref.message)
              ..free(result);
          });
          when(() => updater.update()).thenReturn(result);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('throws $UpdateException', () async {
          await expectLater(
            shorebirdUpdater.update,
            throwsA(
              isA<UpdateException>()
                  .having((e) => e.message, 'message', 'oops')
                  .having(
                    (e) => e.reason,
                    'reason',
                    UpdateFailureReason.installFailed,
                  ),
            ),
          );
          verify(updater.update).called(1);
          verify(() => updater.freeUpdateResult(any())).called(1);
        });
      });

      group('when an unknown error occurs', () {
        setUp(() {
          when(() => updater.currentPatchNumber()).thenReturn(0);
          final result = calloc.allocate<UpdateResult>(sizeOf<UpdateResult>());
          result.ref.status = SHOREBIRD_UPDATE_ERROR;
          addTearDown(() => calloc.free(result));
          when(() => updater.update()).thenReturn(result);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('throws $UpdateException', () async {
          await expectLater(
            shorebirdUpdater.update,
            throwsA(
              isA<UpdateException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'An unknown error occurred.',
                  )
                  .having(
                    (e) => e.reason,
                    'reason',
                    UpdateFailureReason.unknown,
                  ),
            ),
          );
          verify(updater.update).called(1);
          verify(() => updater.freeUpdateResult(any())).called(1);
        });
      });

      group('when an outdated version of the engine is used', () {
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(0);
          when(updater.nextPatchNumber).thenReturn(1);
          when(() => updater.update()).thenThrow(Exception('oops'));
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('falls back to downloadUpdate', () async {
          await expectLater(shorebirdUpdater.update(), completes);
          verify(updater.update).called(1);
          verify(updater.downloadUpdate).called(1);
          verifyNever(() => updater.freeUpdateResult(any()));
        });

        group('when update fails', () {
          setUp(() {
            when(updater.currentPatchNumber).thenReturn(0);
            when(updater.nextPatchNumber).thenReturn(0);
            shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
          });

          test('throws if legacy update fails', () async {
            await expectLater(
              shorebirdUpdater.update,
              throwsA(
                isA<UpdateException>().having(
                  (e) => e.message,
                  'message',
                  '''
Downloading update failed but reason is unknown due to legacy updater.
Please upgrade the Shorebird Engine for improved error messages.''',
                ).having(
                  (e) => e.reason,
                  'reason',
                  UpdateFailureReason.unknown,
                ),
              ),
            );
            verify(updater.update).called(1);
            verify(updater.downloadUpdate).called(1);
            verifyNever(() => updater.freeUpdateResult(any()));
          });
        });
      });

      group('when an unsupported status code is returned', () {
        setUp(() {
          when(() => updater.currentPatchNumber()).thenReturn(0);
          final result = calloc.allocate<UpdateResult>(sizeOf<UpdateResult>());
          result.ref.status = -42; // invalid status code
          result.ref.message = nullptr;
          addTearDown(() => calloc.free(result));
          when(() => updater.update()).thenReturn(result);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('throws $UpdateException', () async {
          await expectLater(
            shorebirdUpdater.update,
            throwsA(
              isA<UpdateException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'An unknown error occurred.',
                  )
                  .having(
                    (e) => e.reason,
                    'reason',
                    UpdateFailureReason.unknown,
                  ),
            ),
          );
          verify(updater.update).called(1);
          verify(() => updater.freeUpdateResult(any())).called(1);
        });
      });

      group('when download succeeds', () {
        setUp(() {
          when(updater.currentPatchNumber).thenReturn(0);
          final result = calloc.allocate<UpdateResult>(sizeOf<UpdateResult>());
          result.ref.status = SHOREBIRD_UPDATE_INSTALLED;
          addTearDown(() => calloc.free(result));
          when(() => updater.update()).thenReturn(result);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('completes', () async {
          await expectLater(shorebirdUpdater.update(), completes);
          verify(updater.update).called(1);
          verify(() => updater.freeUpdateResult(any())).called(1);
        });
      });

      group('when a track is provided', () {
        const track = UpdateTrack.beta;

        setUp(() {
          when(updater.currentPatchNumber).thenReturn(0);
          final result = calloc.allocate<UpdateResult>(sizeOf<UpdateResult>());
          result.ref.status = SHOREBIRD_UPDATE_INSTALLED;
          addTearDown(() => calloc.free(result));
          when(() => updater.update(track: track)).thenReturn(result);
          shorebirdUpdater = ShorebirdUpdaterImpl(updater: updater, run: run);
        });

        test('forwards the provided track to the underlying updater call',
            () async {
          await expectLater(
            shorebirdUpdater.update(track: track),
            completes,
          );
          verify(() => updater.update(track: track)).called(1);
          verify(() => updater.freeUpdateResult(any())).called(1);
        });
      });
    });
  });
}
