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
  });
}
