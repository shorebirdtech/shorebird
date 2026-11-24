import 'dart:io';

import 'package:elf/elf.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/symbols/sbsymbols.dart';
import 'package:shorebird_cli/src/symbols/symbol_extractor.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(SymbolExtractor, () {
    const extractor = SymbolExtractor();

    late Directory workingDirectory;
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    setUp(() {
      workingDirectory = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
    });

    File debugInfo({List<ElfSymbolSpec> staticSymbols = const []}) =>
        File(p.join(workingDirectory.path, 'app.android-arm64.symbols'))
          ..writeAsBytesSync(ElfBuilder.build(staticSymbols: staticSymbols));

    File output() =>
        File(p.join(workingDirectory.path, 'out', 'app.sbsymbols'));

    group('writeIndex', () {
      test('writes the index of the functions the debug info names', () {
        final index = runWithOverrides(
          () => extractor.writeIndex(
            debugInfo: debugInfo(
              staticSymbols: const [
                ElfSymbolSpec(name: 'main', value: 0x1200, size: 0x40),
                ElfSymbolSpec(name: 'other', value: 0x1240, size: 0x20),
              ],
            ),
            output: output(),
            image: SymbolImage.release,
          ),
        );

        expect(index, isNotNull);
        expect(
          index!.readAsBytesSync(),
          equals(
            encodeSbsymbols({
              SymbolImage.release: const [
                (start: 0x1200, size: 0x40, name: 'main'),
                (start: 0x1240, size: 0x20, name: 'other'),
              ],
            }),
          ),
        );
      });

      test('measures the ranges against the image it is given', () {
        final index = runWithOverrides(
          () => extractor.writeIndex(
            debugInfo: debugInfo(
              staticSymbols: const [
                ElfSymbolSpec(name: 'main', value: 0x1200, size: 0x40),
              ],
            ),
            output: output(),
            image: SymbolImage.vmcode,
          ),
        );

        expect(
          index!.readAsBytesSync(),
          equals(
            encodeSbsymbols({
              SymbolImage.vmcode: const [
                (start: 0x1200, size: 0x40, name: 'main'),
              ],
            }),
          ),
        );
      });

      test('leaves out everything that is not a sized, named function', () {
        final index = runWithOverrides(
          () => extractor.writeIndex(
            debugInfo: debugInfo(
              staticSymbols: const [
                ElfSymbolSpec(
                  name: 'a_table',
                  value: 0x2000,
                  size: 0x10,
                  type: ElfSymbolType.object,
                ),
                ElfSymbolSpec(name: 'zero_size', value: 0x1200, size: 0),
                ElfSymbolSpec(name: '', value: 0x1100, size: 0x10),
                ElfSymbolSpec(name: 'main', value: 0x1200, size: 0x40),
              ],
            ),
            output: output(),
            image: SymbolImage.release,
          ),
        );

        expect(
          index!.readAsBytesSync(),
          equals(
            encodeSbsymbols({
              SymbolImage.release: const [
                (start: 0x1200, size: 0x40, name: 'main'),
              ],
            }),
          ),
        );
      });

      test('creates the directory the index goes in', () {
        final target = output();
        expect(target.parent.existsSync(), isFalse);

        runWithOverrides(
          () => extractor.writeIndex(
            debugInfo: debugInfo(
              staticSymbols: const [
                ElfSymbolSpec(name: 'main', value: 0x1200, size: 0x40),
              ],
            ),
            output: target,
            image: SymbolImage.release,
          ),
        );

        expect(target.existsSync(), isTrue);
      });

      group('when the debug info names no functions', () {
        test('returns null and writes nothing', () {
          final target = output();

          expect(
            runWithOverrides(
              () => extractor.writeIndex(
                debugInfo: debugInfo(),
                output: target,
                image: SymbolImage.release,
              ),
            ),
            isNull,
          );
          expect(target.existsSync(), isFalse);
        });
      });

      group('when the debug info is not an ELF', () {
        late File notAnElf;

        setUp(() {
          notAnElf = File(
            p.join(workingDirectory.path, 'app.ios-arm64.symbols'),
          )..writeAsStringSync('a Mach-O dSYM, as far as this is concerned');
        });

        test('returns null and says so at --verbose', () {
          expect(
            runWithOverrides(
              () => extractor.writeIndex(
                debugInfo: notAnElf,
                output: output(),
                image: SymbolImage.release,
              ),
            ),
            isNull,
          );
          verify(
            () => logger.detail(
              any(that: contains('is not readable as an ELF')),
            ),
          ).called(1);
        });
      });
    });

    group('compress', () {
      test('writes the gzipped source and returns it', () {
        final source = File(p.join(workingDirectory.path, 'app.symbols'))
          ..writeAsBytesSync(List<int>.filled(1024, 7));
        final destination = File(
          p.join(workingDirectory.path, 'out', 'app.symbols'),
        );

        final compressed = extractor.compress(
          source: source,
          destination: destination,
        );

        expect(compressed.path, equals(destination.path));
        expect(
          gzip.decode(compressed.readAsBytesSync()),
          equals(source.readAsBytesSync()),
        );
      });
    });
  });
}
