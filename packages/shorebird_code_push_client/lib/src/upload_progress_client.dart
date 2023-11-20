import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template upload_progress_http_client}
/// Based on the [IOClient] from the `http` package. The primary difference is
/// that this implementation uses `stream.addStream` instead of `stream.pipe`
/// to allow for progress reporting.
/// {@endtemplate}
class UploadProgressHttpClient extends http.BaseClient {
  /// {@macro upload_progress_http_client}
  UploadProgressHttpClient([HttpClient? inner])
      : _inner = inner ?? HttpClient(),
        _uploadProgressController =
            StreamController<DataTransferProgress>.broadcast();

  /// The underlying `dart:io` HTTP client.
  HttpClient? _inner;

  final StreamController<DataTransferProgress> _uploadProgressController;

  /// Publishes data transfer progress updates.
  Stream<DataTransferProgress> get progressStream =>
      _uploadProgressController.stream;

  /// Sends an HTTP request and asynchronously returns the response.
  @override
  Future<IOStreamedResponse> send(http.BaseRequest request) async {
    final stream = request.finalize();

    try {
      final ioRequest = (await _inner!.openUrl(request.method, request.url))
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..contentLength = (request.contentLength ?? -1)
        ..persistentConnection = request.persistentConnection;
      request.headers.forEach((name, value) {
        ioRequest.headers.set(name, value);
      });

      final totalBytes = request.contentLength ?? 0;
      var bytesTransferred = 0;

      await ioRequest.addStream(
        stream.map((chunk) {
          bytesTransferred += chunk.length;
          _uploadProgressController.add(
            DataTransferProgress(
              bytesTransferred: bytesTransferred,
              totalBytes: totalBytes,
              url: request.url,
            ),
          );
          return chunk;
        }),
      );

      final response = await ioRequest.close();

      final headers = <String, String>{};
      response.headers.forEach((key, values) {
        headers[key] = values.join(',');
      });

      return IOStreamedResponse(
        response.handleError(
          (Object error) {
            final httpException = error as HttpException;
            throw http.ClientException(
              httpException.message,
              httpException.uri,
            );
          },
          test: (error) => error is HttpException,
        ),
        response.statusCode,
        contentLength:
            response.contentLength == -1 ? null : response.contentLength,
        request: request,
        headers: headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        inner: response,
      );
    } on SocketException catch (error) {
      throw http.ClientException(error.message, request.url);
    } on HttpException catch (error) {
      throw http.ClientException(error.message, error.uri);
    }
  }

  /// Closes the client.
  ///
  /// Terminates all active connections. If a client remains unclosed, the Dart
  /// process may not terminate.
  @override
  void close() {
    if (_inner != null) {
      _inner!.close(force: true);
      _inner = null;
    }
  }
}
