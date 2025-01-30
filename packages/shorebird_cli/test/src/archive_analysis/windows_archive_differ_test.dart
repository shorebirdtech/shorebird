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
      test('returns false', () {
        expect(differ.isNativeFilePath(r'C:\path\to\file.exe'), isFalse);
      });
    });
  });
}
