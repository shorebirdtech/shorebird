// cspell:words adrp cstring dynsym insn Lcom libnative methname objc rodata
// cspell:words sbbr symtab
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dex/dex.dart';
import 'package:elf/elf.dart';
import 'package:macho/macho.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/dart_bridge_analyzer.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(DartBridgeAnalyzer, () {
    const analyzer = DartBridgeAnalyzer();

    group('value types', () {
      test('supports value equality and getters', () {
        const ffi = DartFfiNativeSymbol(
          symbol: 'native_add',
          dartName: 'nativeAdd',
          assetId: 'package:my_app/native.dart',
        );
        const channel = DartPlatformChannel(
          name: 'com.example/battery',
          kind: DartChannelKind.methodChannel,
        );
        const contract = DartBridgeContract(
          ffiSymbols: [ffi],
          channels: [channel],
        );
        const diagnostic = DartBridgeDiagnostic(
          kind: DartBridgeDiagnosticKind.modifiedPlatformChannel,
          symbolOrChannel: 'com.example/battery',
          channelKind: DartChannelKind.methodChannel,
          owner: 'Lcom/example/BatteryPlugin;',
          message: '[CRASH RISK] test message',
        );
        const result = DartBridgeAnalysisResult(
          contract: contract,
          diagnostics: [diagnostic],
        );
        const emptyResult = DartBridgeAnalysisResult.empty();

        expect(
          ffi,
          equals(
            const DartFfiNativeSymbol(
              symbol: 'native_add',
              dartName: 'nativeAdd',
              assetId: 'package:my_app/native.dart',
            ),
          ),
        );
        expect(
          channel,
          equals(
            const DartPlatformChannel(
              name: 'com.example/battery',
              kind: DartChannelKind.methodChannel,
            ),
          ),
        );
        expect(contract.ffiNativeSymbolNames, equals({'native_add'}));
        expect(contract.channelNames, equals({'com.example/battery'}));
        expect(contract.isEmpty, isFalse);
        expect(const DartBridgeContract().isEmpty, isTrue);
        expect(
          contract,
          equals(
            const DartBridgeContract(
              ffiSymbols: [ffi],
              channels: [channel],
            ),
          ),
        );
        expect(diagnostic.describe(), equals('[CRASH RISK] test message'));
        expect(
          diagnostic,
          equals(
            const DartBridgeDiagnostic(
              kind: DartBridgeDiagnosticKind.modifiedPlatformChannel,
              symbolOrChannel: 'com.example/battery',
              channelKind: DartChannelKind.methodChannel,
              owner: 'Lcom/example/BatteryPlugin;',
              message: '[CRASH RISK] test message',
            ),
          ),
        );
        expect(result.isSafe, isFalse);
        expect(result.hasCrashRisks, isTrue);
        expect(
          result,
          equals(
            const DartBridgeAnalysisResult(
              contract: contract,
              diagnostics: [diagnostic],
            ),
          ),
        );
        expect(emptyResult.isSafe, isTrue);
        expect(emptyResult.hasCrashRisks, isFalse);
        expect(emptyResult.contract.isEmpty, isTrue);
      });
    });

    group('DillKernelBuilder and parseDill', () {
      test(
        'round-trips @Native symbols, channels, and multi-byte Kernel UInts',
        () {
          final mediumString = 'm' * 200; // 2-byte Kernel UInt (>= 0x80)
          final largeString = 'L' * 17000; // 4-byte Kernel UInt (>= 0x4000)
          final builder = DillKernelBuilder()
            ..addFfiNativeSymbol(
              'native_calc',
              dartName: 'nativeCalc',
              assetId: 'package:calc/calc.dart',
            )
            ..addFfiNativeSymbol('native_simple')
            ..addMethodChannel('com.example/method')
            ..addMethodChannel('dev.flutter.pigeon.pkg.Api.viaMethod')
            ..addEventChannel('com.example/events')
            ..addBasicMessageChannel('com.example/basic')
            ..addBasicMessageChannel('dev.flutter.pigeon.pkg.Api.viaBasic')
            ..addPigeonChannel('dev.flutter.pigeon.pkg.Api.explicit')
            ..addRawString('dev.flutter.pigeon.pkg.Api.fromStringTable')
            ..addRawString(mediumString)
            ..addRawString(largeString);

          final bytes = builder.build();
          final contract = analyzer.parseDill(bytes);

          expect(
            contract.ffiSymbols,
            equals(const [
              DartFfiNativeSymbol(
                symbol: 'native_calc',
                dartName: 'nativeCalc',
                assetId: 'package:calc/calc.dart',
              ),
              DartFfiNativeSymbol(symbol: 'native_simple'),
            ]),
          );
          expect(
            contract.channels,
            equals(const [
              DartPlatformChannel(
                name: 'com.example/method',
                kind: DartChannelKind.methodChannel,
              ),
              DartPlatformChannel(
                name: 'dev.flutter.pigeon.pkg.Api.viaMethod',
                kind: DartChannelKind.pigeon,
              ),
              DartPlatformChannel(
                name: 'com.example/events',
                kind: DartChannelKind.eventChannel,
              ),
              DartPlatformChannel(
                name: 'com.example/basic',
                kind: DartChannelKind.basicMessageChannel,
              ),
              DartPlatformChannel(
                name: 'dev.flutter.pigeon.pkg.Api.viaBasic',
                kind: DartChannelKind.pigeon,
              ),
              DartPlatformChannel(
                name: 'dev.flutter.pigeon.pkg.Api.explicit',
                kind: DartChannelKind.pigeon,
              ),
              DartPlatformChannel(
                name: 'dev.flutter.pigeon.pkg.Api.fromStringTable',
                kind: DartChannelKind.pigeon,
              ),
            ]),
          );
        },
      );

      test('parses a minimal .dill with an empty StringTable', () {
        final bytes = Uint8List.fromList([
          0x90, 0xab, 0xcd, 0xef, // magic
          0x00, 0x00, 0x00, 0x78, // version 120
          0x00, // stringCount = 0
        ]);
        final contract = analyzer.parseDill(bytes);
        expect(contract.isEmpty, isTrue);
      });

      group('when .dill binary is malformed or truncated', () {
        test('throws FormatException on fewer than 8 bytes', () {
          expect(
            () => analyzer.parseDill(Uint8List.fromList([0x90, 0xab])),
            throwsFormatException,
          );
        });

        test('throws FormatException on invalid magic bytes', () {
          expect(
            () => analyzer.parseDill(
              Uint8List.fromList([0xde, 0xad, 0xbe, 0xef, 0, 0, 0, 1]),
            ),
            throwsFormatException,
          );
        });

        test('throws FormatException on truncated UInt', () {
          expect(
            () => analyzer.parseDill(
              Uint8List.fromList([
                0x90, 0xab, 0xcd, 0xef,
                0x00, 0x00, 0x00, 0x78,
                0x80, // 2-byte UInt missing second byte
              ]),
            ),
            throwsFormatException,
          );
        });

        test('throws FormatException on non-monotonic string end offsets', () {
          expect(
            () => analyzer.parseDill(
              Uint8List.fromList([
                0x90, 0xab, 0xcd, 0xef,
                0x00, 0x00, 0x00, 0x78,
                0x02, // 2 strings
                0x05, // endOffset[0] = 5
                0x03, // endOffset[1] = 3 (< 5)
              ]),
            ),
            throwsFormatException,
          );
        });

        test('throws FormatException on truncated UTF-8 string payload', () {
          expect(
            () => analyzer.parseDill(
              Uint8List.fromList([
                0x90, 0xab, 0xcd, 0xef,
                0x00, 0x00, 0x00, 0x78,
                0x01, // 1 string
                0x10, // endOffset[0] = 16 bytes, but 0 bytes follow
              ]),
            ),
            throwsFormatException,
          );
        });

        test('throws FormatException on out-of-bounds FFI pragma/symbol', () {
          expect(
            () => analyzer.parseDill(
              Uint8List.fromList([
                0x90, 0xab, 0xcd, 0xef,
                0x00, 0x00, 0x00, 0x78,
                0x00, // 0 strings
                0x53, 0x42, 0x42, 0x52, // 'SBBR'
                0x01, // 1 FFI entry
                0x00, // pragmaIdx = 0 (out of bounds)
                0x00,
                0x00,
                0x00,
              ]),
            ),
            throwsFormatException,
          );
        });

        test('throws FormatException on out-of-bounds dartName index', () {
          expect(
            () => analyzer.parseDill(
              Uint8List.fromList([
                0x90, 0xab, 0xcd, 0xef,
                0x00, 0x00, 0x00, 0x78,
                0x01, // 1 string
                0x01, // endOffset = 1
                0x61, // 'a'
                0x53, 0x42, 0x42, 0x52, // 'SBBR'
                0x01, // 1 FFI entry
                0x00, // pragmaIdx = 0
                0x00, // symbolIdx = 0
                0x05, // dartNameIdxPlusOne = 5 (idx 4 >= 1)
                0x00,
              ]),
            ),
            throwsFormatException,
          );
        });

        test('throws FormatException on out-of-bounds assetId index', () {
          expect(
            () => analyzer.parseDill(
              Uint8List.fromList([
                0x90, 0xab, 0xcd, 0xef,
                0x00, 0x00, 0x00, 0x78,
                0x01, // 1 string
                0x01, // endOffset = 1
                0x61, // 'a'
                0x53, 0x42, 0x42, 0x52, // 'SBBR'
                0x01, // 1 FFI entry
                0x00, // pragmaIdx = 0
                0x00, // symbolIdx = 0
                0x01, // dartNameIdxPlusOne = 1 (idx 0, valid)
                0x05, // assetIdIdxPlusOne = 5 (idx 4 >= 1)
              ]),
            ),
            throwsFormatException,
          );
        });

        test('ignores FFI entry whose pragma is not vm:ffi:native', () {
          final contract = analyzer.parseDill(
            Uint8List.fromList([
              0x90, 0xab, 0xcd, 0xef,
              0x00, 0x00, 0x00, 0x78,
              0x01, // 1 string
              0x01, // endOffset = 1
              0x61, // 'a' (not 'vm:ffi:native')
              0x53, 0x42, 0x42, 0x52, // 'SBBR'
              0x01, // 1 FFI entry
              0x00, // pragmaIdx = 0
              0x00, // symbolIdx = 0
              0x00,
              0x00,
              0x00, // 0 channels
            ]),
          );
          expect(contract.ffiSymbols, isEmpty);
        });

        test('throws FormatException on out-of-bounds channel index', () {
          expect(
            () => analyzer.parseDill(
              Uint8List.fromList([
                0x90, 0xab, 0xcd, 0xef,
                0x00, 0x00, 0x00, 0x78,
                0x01, // 1 string
                0x01, // endOffset = 1
                0x61, // 'a'
                0x53, 0x42, 0x42, 0x52, // 'SBBR'
                0x00, // 0 FFI entries
                0x01, // 1 channel entry
                0x00, // kindIdx = 0
                0x05, // nameIdx = 5 (out of bounds)
              ]),
            ),
            throwsFormatException,
          );
        });
      });
    });

    group('analyze', () {
      test('skips enrichment gracefully when .dill is corrupt', () {
        final result = analyzer.analyze(
          dillBytes: Uint8List.fromList([0x00, 0x01, 0x02]),
          releaseSymbols: const {'native_add'},
        );
        expect(result.isSafe, isTrue);
        expect(result.contract.isEmpty, isTrue);
      });

      test('returns safe result when .dill contract is empty', () {
        final result = analyzer.analyze(
          dillBytes: DillKernelBuilder().build(),
          releaseSymbols: const {'native_add'},
        );
        expect(result.isSafe, isTrue);
        expect(result.diagnostics, isEmpty);
      });

      group('@Native (vm:ffi:native) symbol verification', () {
        test(
          'safe mock: passes when @Native symbols exist in ELF, Mach-O, '
          'and archive release binaries',
          () {
            final dillBytes =
                (DillKernelBuilder()
                      ..addFfiNativeSymbol('direct_sym')
                      ..addFfiNativeSymbol('rust_hash')
                      ..addFfiNativeSymbol('static_helper')
                      ..addFfiNativeSymbol('objc_bridge')
                      ..addFfiNativeSymbol('_underscore_sym')
                      ..addFfiNativeSymbol('archive_sym'))
                    .build();

            final elfBytes = ElfBuilder.build(
              symbols: const [
                ElfSymbolSpec(
                  name: 'rust_hash',
                ),
              ],
              staticSymbols: const [
                ElfSymbolSpec(
                  name: 'static_helper',
                  value: 0x1008,
                ),
              ],
            );

            final machOBytes = MachOBuilder.buildThin(
              symbols: const [
                MachOSymbolSpec(name: '_objc_bridge'),
              ],
              exportedSymbols: const [
                MachOExportedSymbol(
                  name: 'underscore_sym',
                  offset: 0x1008,
                  flags: 0,
                ),
              ],
            );

            final archiveElfBytes = ElfBuilder.build(
              symbols: const [
                ElfSymbolSpec(
                  name: 'archive_sym',
                ),
              ],
            );
            final archiveMachOBytes = MachOBuilder.buildThin(
              symbols: const [
                MachOSymbolSpec(name: '_runner_sym'),
              ],
            );

            final archive = Archive()
              ..addFile(
                ArchiveFile('base/lib/', 0, Uint8List(0))..isFile = false,
              )
              ..addFile(
                ArchiveFile(
                  'base/lib/arm64-v8a/libapp.so',
                  4,
                  Uint8List.fromList([1, 2, 3, 4]),
                ),
              )
              ..addFile(
                ArchiveFile(
                  'base/lib/arm64-v8a/libnative.so',
                  archiveElfBytes.length,
                  archiveElfBytes,
                ),
              )
              ..addFile(
                ArchiveFile(
                  'Products/Applications/Runner.app/Runner',
                  archiveMachOBytes.length,
                  archiveMachOBytes,
                ),
              );

            final tempDir = Directory.systemTemp.createTempSync();
            final archiveFile = File(p.join(tempDir.path, 'release.zip'))
              ..writeAsBytesSync(ZipEncoder().encode(archive));

            final result = analyzer.analyze(
              dillBytes: dillBytes,
              releaseSymbols: const {'direct_sym'},
              releaseElfBinaries: [
                elfBytes,
                Uint8List.fromList([0x00, 0x01]), // corrupt ELF ignored
              ],
              releaseMachOBinaries: [
                machOBytes,
                Uint8List.fromList([0x00, 0x01]), // corrupt Mach-O ignored
              ],
              releaseArchivePath: archiveFile.path,
            );

            expect(result.isSafe, isTrue);
            expect(result.diagnostics, isEmpty);
            expect(result.props, isNotEmpty);
            expect(result.contract.props, isNotEmpty);
          },
        );

        test(
          'adversarial mock: flags missing @Native symbols and undefined '
          'SHN_UNDEF imports with [CRASH RISK]',
          () {
            final dillBytes =
                (DillKernelBuilder()
                      ..addFfiNativeSymbol('existing_fn')
                      ..addFfiNativeSymbol('missing_ffi_fn')
                      ..addFfiNativeSymbol('imported_only_fn'))
                    .build();

            final elfBytes = ElfBuilder.build(
              symbols: const [
                ElfSymbolSpec(
                  name: 'existing_fn',
                ),
                ElfSymbolSpec.undefined('imported_only_fn'),
              ],
            );

            final result = analyzer.analyze(
              dillBytes: dillBytes,
              releaseElfBinaries: [elfBytes],
              releaseArchivePath: 'non_existent_archive.aab',
            );

            expect(result.isSafe, isFalse);
            expect(result.hasCrashRisks, isTrue);
            expect(
              result.diagnostics.map((d) => d.symbolOrChannel),
              equals(['missing_ffi_fn', 'imported_only_fn']),
            );
            expect(
              result.diagnostics.first.kind,
              equals(DartBridgeDiagnosticKind.missingFfiSymbol),
            );
            expect(
              result.diagnostics.first.describe(),
              contains('[CRASH RISK] @Native symbol "missing_ffi_fn"'),
            );
          },
        );
      });

      group('platform channel and Pigeon contract verification', () {
        test(
          'safe mock: passes when only unrelated native classes changed',
          () {
            final dillBytes =
                (DillKernelBuilder()
                      ..addMethodChannel('com.example/battery')
                      ..addEventChannel('com.example/charging')
                      ..addBasicMessageChannel('com.example/raw')
                      ..addPigeonChannel(
                        'dev.flutter.pigeon.example.BatteryHostApi.getLevel',
                      ))
                    .build();

            const androidDiff = AndroidFileSetDiff(
              addedPaths: {},
              removedPaths: {},
              changedPaths: {'base/dex/classes.dex'},
              dexDiffResults: {
                'base/dex/classes.dex': DexDiffResult(
                  differences: [
                    DexDifference(
                      kind: DexDifferenceKind.bytecodeChanged,
                      description:
                          'Lcom/example/ThemeHelper;: bytecode changed in '
                          'Lcom/example/ThemeHelper;.apply()V',
                    ),
                    DexDifference(
                      kind: DexDifferenceKind.classAdded,
                      description: 'Class added: Lcom/example/AbPlugin;',
                    ),
                  ],
                ),
              },
            );

            final result = analyzer.analyze(
              dillBytes: dillBytes,
              changedClasses: const {'   ', 'UnrelatedWidget'},
              channelOwners: const {
                'com.example/battery': {'Lcom/example/BatteryOwner;'},
              },
              fileSetDiff: androidDiff,
            );

            expect(result.isSafe, isTrue);
            expect(result.diagnostics, isEmpty);
          },
        );

        test(
          'adversarial mock: flags MethodChannel, EventChannel, '
          'BasicMessageChannel, and Pigeon channels touched by Android DEX '
          'and ELF diffs',
          () {
            final dillBytes =
                (DillKernelBuilder()
                      ..addMethodChannel('com.example/battery')
                      ..addMethodChannel('com.example/ExactMatch')
                      ..addEventChannel('com.example/charging')
                      ..addBasicMessageChannel('com.example/native_elf')
                      ..addMethodChannel('com.example/explicit_owner')
                      ..addPigeonChannel(
                        'dev.flutter.pigeon.example.BatteryHostApi.getLevel',
                      ))
                    .build();

            const androidDiff = AndroidFileSetDiff(
              addedPaths: {},
              removedPaths: {},
              changedPaths: {
                'base/dex/classes.dex',
                'base/lib/arm64-v8a/libnative.so',
              },
              dexDiffResults: {
                'base/dex/classes.dex': DexDiffResult(
                  differences: [
                    DexDifference(
                      kind: DexDifferenceKind.bytecodeChanged,
                      description:
                          'Lcom/example/BatteryPlugin;: bytecode changed',
                      codeDiff: DexCodeDiff(
                        oldRegion: [
                          DexCanonicalInstruction(
                            address: 0,
                            tokens: '26,S:com.example/charging,',
                          ),
                        ],
                      ),
                    ),
                    DexDifference(
                      kind: DexDifferenceKind.methodAdded,
                      description: 'Lcom/example/ExactMatch;: method added',
                    ),
                    DexDifference(
                      kind: DexDifferenceKind.bytecodeChanged,
                      description:
                          r'Lcom/example/Messages$BatteryHostApi;: '
                          'bytecode changed',
                    ),
                  ],
                ),
              },
              elfDiffResults: {
                'base/lib/arm64-v8a/libnative.so': ElfDiffResult(
                  differences: [
                    ElfDifference(
                      kind: ElfDifferenceKind.functionCodeChanged,
                      description: 'Function code changed in register_channel',
                      codeDiff: ElfCodeDiff(
                        newRegion: [
                          ElfCanonicalInstruction(
                            address: 0,
                            tokens: 'adrp,S:com.example/native_elf,',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              },
            );

            final result = analyzer.analyze(
              dillBytes: dillBytes,
              changedClasses: const {'Lcom/example/ExplicitChannelBridge;'},
              channelOwners: const {
                'com.example/explicit_owner': {
                  'Lcom/example/ExplicitChannelBridge;',
                },
              },
              fileSetDiff: androidDiff,
            );

            expect(result.isSafe, isFalse);
            expect(result.diagnostics.first.props, isNotEmpty);
            expect(
              result.diagnostics.map((d) => d.symbolOrChannel).toList(),
              equals([
                'com.example/battery',
                'com.example/ExactMatch',
                'com.example/charging',
                'com.example/native_elf',
                'com.example/explicit_owner',
                'dev.flutter.pigeon.example.BatteryHostApi.getLevel',
              ]),
            );
            for (final diagnostic in result.diagnostics) {
              expect(
                diagnostic.kind,
                equals(DartBridgeDiagnosticKind.modifiedPlatformChannel),
              );
              expect(diagnostic.describe(), startsWith('[CRASH RISK]'));
            }
          },
        );

        test(
          'adversarial mock: flags channels touched by Apple Mach-O diffs',
          () {
            final dillBytes =
                (DillKernelBuilder()
                      ..addMethodChannel('com.example/camera')
                      ..addEventChannel('com.example/ios_stream')
                      ..addBasicMessageChannel('com.example/macho_insn'))
                    .build();

            const appleDiff = AppleFileSetDiff(
              addedPaths: {},
              removedPaths: {},
              changedPaths: {'Products/Applications/Runner.app/Runner'},
              machODiffResults: {
                'Products/Applications/Runner.app/Runner': MachODiffResult(
                  differences: [
                    MachODifference(
                      kind: MachODifferenceKind.objcClassAdded,
                      description:
                          'Objective-C class added: example.CameraPlugin',
                    ),
                    MachODifference(
                      kind: MachODifferenceKind.cstringLiteralChanged,
                      description:
                          'C string literal added: "com.example/ios_stream"',
                    ),
                    MachODifference(
                      kind: MachODifferenceKind.functionCodeChanged,
                      description: 'Function code changed in _setup',
                      codeDiff: MachOCodeDiff(
                        oldRegion: [
                          MachOCanonicalInstruction(
                            address: 0,
                            tokens: 'adrp,S:com.example/macho_insn,',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              },
            );

            final result = analyzer.analyze(
              dillBytes: dillBytes,
              fileSetDiff: appleDiff,
            );

            expect(result.isSafe, isFalse);
            expect(result.diagnostics.first.props, isNotEmpty);
            expect(
              result.diagnostics.map((d) => d.symbolOrChannel).toList(),
              equals([
                'com.example/camera',
                'com.example/ios_stream',
                'com.example/macho_insn',
              ]),
            );
          },
        );
      });
    });
  });
}
