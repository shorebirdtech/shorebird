import 'package:cloud_logger/cloud_logger.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../helpers/helpers.dart';

void main() {
  group('requestLogger', () {
    test(
      'uses default logger when projectId is null',
      overridePrint((logs) async {
        final request = Request('GET', Uri.parse('http://localhost/'));
        final middleware = requestLogger();
        Response handler(Request request) {
          logger.info('info');
          return Response.ok('');
        }

        await middleware(handler)(request);
        expect(logs.length, equals(2));
        expect(logs.first, equals('[INFO]: info'));
        expect(logs.last, contains('GET     [200] /'));
      }),
    );

    test(
      'uses cloud logger when projectId is specified (print)',
      overridePrint((logs) async {
        const projectId = 'my.project.id';
        final request = Request('GET', Uri.parse('http://localhost/'));
        final middleware = requestLogger(projectId);
        Response handler(Request request) {
          // ignore: avoid_print
          print('hello');
          return Response.ok('');
        }

        await middleware(handler)(request);
        expect(logs.length, equals(1));
        expect(logs.first, equals('{"message":"hello","severity":"INFO"}'));
      }),
    );

    test(
      'uses cloud logger when projectId is specified (info)',
      overridePrint((logs) async {
        const projectId = 'my.project.id';
        final request = Request('GET', Uri.parse('http://localhost/'));
        final middleware = requestLogger(projectId);
        Response handler(Request request) {
          logger.info('info');
          return Response.ok('');
        }

        await middleware(handler)(request);
        expect(logs.length, equals(1));
        expect(logs.first, equals('{"message":"info","severity":"INFO"}'));
      }),
    );

    test(
      'uses cloud logger when projectId is specified (error)',
      overridePrint((logs) async {
        const traceId = '0679686673a';
        const projectId = 'my.project.id';
        final request = Request(
          'GET',
          Uri.parse('http://localhost/'),
          headers: {
            'x-cloud-trace-context': traceId,
          },
        );
        final middleware = requestLogger(projectId);
        Response handler(Request request) {
          throw Exception('oops');
        }

        await middleware(handler)(request);
        expect(logs.length, equals(1));
        expect(
          logs.first,
          contains(
            r'"message":"Exception: oops\ntest/src/request_logger_test.dart',
          ),
        );
        expect(logs.first, contains('"severity":"ERROR"'));
        expect(
          logs.first,
          contains(
            '"logging.googleapis.com/trace":"projects/my.project.id/traces/0679686673a"',
          ),
        );
        expect(
          logs.first,
          contains(
            '"logging.googleapis.com/sourceLocation":{"file":"test/src/request_logger_test.dart"',
          ),
        );
      }),
    );
  });
}
