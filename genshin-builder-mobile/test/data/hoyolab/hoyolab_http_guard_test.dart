import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_http_guard.dart';

void main() {
  group('HoyolabHttpGuard', () {
    test('accepts valid JSON object responses', () {
      final response = http.Response(
        jsonEncode({
          'retcode': 0,
          'message': 'OK',
          'data': {'list': []},
        }),
        200,
      );

      expect(
        HoyolabHttpGuard.decodeJsonObject(response)['retcode'],
        0,
      );
    });

    for (final status in [401, 403, 429, 500, 502, 503, 504]) {
      test('rejects HTTP $status before JSON parsing', () {
        final response = http.Response('<html>secret</html>', status);
        expect(
          () => HoyolabHttpGuard.decodeJsonObject(response),
          throwsA(
            isA<HoyolabHttpException>().having(
              (error) => error.failure,
              'failure',
              HoyolabHttpFailure.httpStatus,
            ),
          ),
        );
      });
    }

    test('rejects HTML and empty bodies without exposing content', () {
      for (final body in ['', '<html>error</html>', '   <html/>']) {
        final response = http.Response(body, 200);
        expect(
          () => HoyolabHttpGuard.decodeJsonObject(response),
          throwsA(isA<HoyolabHttpException>()),
        );
      }
    });

    test('rejects malformed JSON and invalid root types', () {
      for (final body in ['{', '[]', '"string"']) {
        final response = http.Response(body, 200);
        expect(
          () => HoyolabHttpGuard.decodeJsonObject(response),
          throwsA(isA<HoyolabHttpException>()),
        );
      }
    });

    test('rejects oversized bodies', () {
      final response = http.Response('x' * (HoyolabHttpGuard.defaultMaxBytes + 1), 200);
      expect(
        () => HoyolabHttpGuard.decodeJsonObject(response),
        throwsA(
          isA<HoyolabHttpException>().having(
            (error) => error.failure,
            'failure',
            HoyolabHttpFailure.responseTooLarge,
          ),
        ),
      );
    });

    test('aborts while streaming when the body exceeds maxBytes', () async {
      final streamed = http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          List<int>.filled(8, 0x61),
          List<int>.filled(8, 0x62),
        ]),
        200,
      );
      await expectLater(
        HoyolabHttpGuard.readBoundedResponse(streamed, maxBytes: 10),
        throwsA(
          isA<HoyolabHttpException>().having(
            (error) => error.failure,
            'failure',
            HoyolabHttpFailure.responseTooLarge,
          ),
        ),
      );
    });

    test('rejects Content-Length above the max before reading', () async {
      final streamed = http.StreamedResponse(
        const Stream<List<int>>.empty(),
        200,
        contentLength: 100,
      );
      await expectLater(
        HoyolabHttpGuard.readBoundedResponse(streamed, maxBytes: 16),
        throwsA(
          isA<HoyolabHttpException>().having(
            (error) => error.failure,
            'failure',
            HoyolabHttpFailure.responseTooLarge,
          ),
        ),
      );
    });

    test('rejects non-HTTPS URIs', () {
      expect(
        () => HoyolabHttpGuard.ensureSafeHoyolabUri(
          Uri.parse('http://example.test/path'),
        ),
        throwsA(
          isA<HoyolabHttpException>().having(
            (error) => error.failure,
            'failure',
            HoyolabHttpFailure.insecureUrl,
          ),
        ),
      );
    });

    test('toString does not include response body or secrets', () {
      const error = HoyolabHttpException(
        HoyolabHttpFailure.httpStatus,
        statusCode: 502,
      );
      expect(error.toString(), 'HoyolabHttpException(httpStatus)');
      expect(error.toString(), isNot(contains('502')));
      expect(error.toString(), isNot(contains('ltoken')));
    });
  });
}
