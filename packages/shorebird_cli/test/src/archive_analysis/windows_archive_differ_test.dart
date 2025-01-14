import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:test/test.dart';

void main() {
  group(WindowsArchiveDiffer, () {
    late WindowsArchiveDiffer differ;

    setUp(() {
      differ = const WindowsArchiveDiffer();
    });

    group('isAssetFilePath', () {
      group('when path contains "flutter_assets"', () {
        test('returns true', () {
          final result = differ.isAssetFilePath('flutter_assets/foo/bar');
          expect(result, isTrue);
        });
      });

      group('when path does not contain "flutter_assets"', () {
        test('returns false', () {
          final result = differ.isAssetFilePath('foo/bar');
          expect(result, isFalse);
        });
      });
    });

    group('isDartFilePath', () {
      group('when file is app.so', () {
        test('returns true', () {
          final result = differ.isDartFilePath('app.so');
          expect(result, isTrue);
        });
      });

      group('when file is not app.so', () {
        test('returns false', () {
          final result = differ.isDartFilePath('foo.so');
          expect(result, isFalse);
        });
      });
    });

    group('isNativeFilePath', () {
      group('when file extension is .dll', () {
        test('returns true', () {
          final result = differ.isNativeFilePath('foo.dll');
          expect(result, isTrue);
        });
      });

      group('when file extension is .exe', () {
        test('returns true', () {
          final result = differ.isNativeFilePath('foo.exe');
          expect(result, isTrue);
        });
      });

      group('when file extension is not .dll or .exe', () {
        test('returns false', () {
          final result = differ.isNativeFilePath('foo.so');
          expect(result, isFalse);
        });
      });
    });

    group('changedFiles', () {
      final winArchivesFixturesBasePath =
          p.join('test', 'fixtures', 'win_archives');
      final releasePath = p.join(
        winArchivesFixturesBasePath,
        'release.zip',
      );
      final patchPath = p.join(
        winArchivesFixturesBasePath,
        'patch.zip',
      );

      test('returns an empty FileSetDiff', () async {
        final result = await differ.changedFiles(releasePath, patchPath);
        expect(result, equals(FileSetDiff.empty()));
      });
    });
  });
}
