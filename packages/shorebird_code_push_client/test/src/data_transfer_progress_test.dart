import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

void main() {
  group(DataTransferProgress, () {
    group('progressPercentage', () {
      test('returns progress as a value between 0 and 100', () {
        final progress = DataTransferProgress(
          bytesTransferred: 5,
          totalBytes: 100,
          url: Uri.parse('http://example.com'),
        );
        expect(progress.progressPercentage, 5);
      });
    });

    group('toString', () {
      test('has a sensible string representation', () {
        final progress = DataTransferProgress(
          bytesTransferred: 5,
          totalBytes: 100,
          url: Uri.parse('http://example.com'),
        );

        expect(
          progress.toString(),
          equals('5/100 (5.0% from http://example.com)'),
        );
      });
    });

    group('equatable', () {
      test('returns true for equal instances', () {
        final progress1 = DataTransferProgress(
          bytesTransferred: 5,
          totalBytes: 100,
          url: Uri.parse('http://example.com'),
        );
        final progress2 = DataTransferProgress(
          bytesTransferred: 5,
          totalBytes: 100,
          url: Uri.parse('http://example.com'),
        );
        expect(progress1, equals(progress2));
      });

      test('returns false for nonequal instances', () {
        final progress1 = DataTransferProgress(
          bytesTransferred: 5,
          totalBytes: 100,
          url: Uri.parse('http://example.com'),
        );
        final progress2 = DataTransferProgress(
          bytesTransferred: 50,
          totalBytes: 100,
          url: Uri.parse('http://example.com'),
        );

        expect(progress1, isNot(equals(progress2)));
      });
    });
  });
}
