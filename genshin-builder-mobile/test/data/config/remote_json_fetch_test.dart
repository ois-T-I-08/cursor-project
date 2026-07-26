import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/config/remote_json_fetch.dart';
import 'package:http/http.dart' as http;

class _StreamClient extends http.BaseClient {
  _StreamClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}

http.StreamedResponse _streamed({
  required int statusCode,
  required List<List<int>> chunks,
  Map<String, String>? headers,
  int? contentLength,
}) {
  final h = <String, String>{...?headers};
  if (contentLength != null) {
    h['content-length'] = '$contentLength';
  }
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable(chunks),
    statusCode,
    headers: h,
    contentLength: contentLength,
  );
}

void main() {
  const kind = 'test_config';
  const maxBytes = 32;

  test('200 normal JSON map', () async {
    final client = _StreamClient(
      (_) async => _streamed(
        statusCode: 200,
        chunks: [utf8.encode('{"ok":true,"n":1}')],
      ),
    );
    final map = await fetchRemoteJsonMap(
      client: client,
      url: 'https://example.test/config.json',
      kind: kind,
      timeout: const Duration(seconds: 5),
      maxBytes: maxBytes,
    );
    expect(map['ok'], isTrue);
  });

  test(
    'rejects non-HTTPS, credentials, fragments, and malformed URLs',
    () async {
      var sendCount = 0;
      final client = _StreamClient((_) async {
        sendCount++;
        return _streamed(statusCode: 200, chunks: [utf8.encode('{}')]);
      });
      for (final url in [
        'http://example.test/config.json',
        'https://user:secret@example.test/config.json',
        'https://example.test/config.json#section',
        'https://',
      ]) {
        await expectLater(
          fetchRemoteJsonMap(
            client: client,
            url: url,
            kind: kind,
            timeout: const Duration(seconds: 5),
            maxBytes: maxBytes,
          ),
          throwsA(
            isA<RemoteJsonFetchException>().having(
              (e) => e.failure,
              'failure',
              RemoteJsonFailureKind.invalidUrl,
            ),
          ),
        );
      }
      expect(sendCount, 0);
    },
  );

  test(
    'does not follow redirects and forwards explicit safe headers',
    () async {
      final client = _StreamClient((request) async {
        expect(request.followRedirects, isFalse);
        expect(request.headers['User-Agent'], 'test-agent');
        return _streamed(statusCode: 302, chunks: [utf8.encode('{}')]);
      });
      await expectLater(
        fetchRemoteJsonMap(
          client: client,
          url: 'https://example.test/config.json',
          kind: kind,
          timeout: const Duration(seconds: 5),
          maxBytes: maxBytes,
          headers: const {'User-Agent': 'test-agent'},
        ),
        throwsA(
          isA<RemoteJsonFetchException>().having(
            (e) => e.failure,
            'failure',
            RemoteJsonFailureKind.httpStatus,
          ),
        ),
      );
    },
  );

  test('rejects root list', () async {
    final client = _StreamClient(
      (_) async => _streamed(statusCode: 200, chunks: [utf8.encode('[1,2]')]),
    );
    expect(
      () => fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.invalidRootType,
        ),
      ),
    );
  });

  test('rejects empty body', () async {
    final client = _StreamClient(
      (_) async => _streamed(statusCode: 200, chunks: [Uint8List(0)]),
    );
    await expectLater(
      fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.invalidJson,
        ),
      ),
    );
  });

  test('rejects HTML', () async {
    final client = _StreamClient(
      (_) async => _streamed(
        statusCode: 200,
        chunks: [utf8.encode('<!DOCTYPE html><html></html>')],
      ),
    );
    await expectLater(
      fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: 1024,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.invalidJson,
        ),
      ),
    );
  });

  test('rejects invalid JSON', () async {
    final client = _StreamClient(
      (_) async =>
          _streamed(statusCode: 200, chunks: [utf8.encode('{not-json')]),
    );
    await expectLater(
      fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.invalidJson,
        ),
      ),
    );
  });

  test('rejects invalid UTF-8', () async {
    final client = _StreamClient(
      (_) async => _streamed(
        statusCode: 200,
        chunks: [
          Uint8List.fromList([0x7B, 0x22, 0x61, 0x22, 0x3A, 0xFF, 0x7D]),
        ],
      ),
    );
    await expectLater(
      fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.invalidEncoding,
        ),
      ),
    );
  });

  test('http 204 / 404 / 500', () async {
    for (final code in [204, 404, 500]) {
      final client = _StreamClient(
        (_) async => _streamed(statusCode: code, chunks: [utf8.encode('')]),
      );
      await expectLater(
        fetchRemoteJsonMap(
          client: client,
          url: 'https://example.test/a',
          kind: kind,
          timeout: const Duration(seconds: 5),
          maxBytes: maxBytes,
        ),
        throwsA(
          isA<RemoteJsonFetchException>()
              .having(
                (e) => e.failure,
                'failure',
                RemoteJsonFailureKind.httpStatus,
              )
              .having((e) => e.statusCode, 'status', code),
        ),
      );
    }
  });

  test('timeout on send', () async {
    final client = _StreamClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _streamed(statusCode: 200, chunks: [utf8.encode('{}')]);
    });
    await expectLater(
      fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(milliseconds: 5),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.timeout,
        ),
      ),
    );
  });

  test('Content-Length over maxBytes rejects without adopting body', () async {
    final client = _StreamClient(
      (_) async => _streamed(
        statusCode: 200,
        contentLength: maxBytes + 1,
        chunks: [utf8.encode('{"huge":true}')],
      ),
    );
    await expectLater(
      fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.responseTooLarge,
        ),
      ),
    );
  });

  test('stream exceeds maxBytes without Content-Length', () async {
    final client = _StreamClient(
      (_) async => _streamed(
        statusCode: 200,
        chunks: [
          utf8.encode('{"a":"'),
          utf8.encode('x' * 40),
          utf8.encode('"}'),
        ],
      ),
    );
    await expectLater(
      fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.responseTooLarge,
        ),
      ),
    );
  });

  test('multiple chunks exactly maxBytes succeeds', () async {
    // {"k":""} is 8 bytes; pad value to reach exactly 32.
    final payload =
        '{"k":"${'a' * 22}"}'; // 8+22=30? {"k":" + 22 + "} = 6+22+2=30
    expect(utf8.encode(payload).length, lessThanOrEqualTo(maxBytes));
    final bytes = utf8.encode(payload);
    final client = _StreamClient(
      (_) async => _streamed(
        statusCode: 200,
        chunks: [bytes.sublist(0, 10), bytes.sublist(10)],
      ),
    );
    final map = await fetchRemoteJsonMap(
      client: client,
      url: 'https://example.test/a',
      kind: kind,
      timeout: const Duration(seconds: 5),
      maxBytes: bytes.length,
    );
    expect(map['k'], 'a' * 22);
  });

  test('multiple chunks maxBytes+1 rejected', () async {
    final bytes = utf8.encode('{"k":"${'b' * 40}"}');
    final client = _StreamClient(
      (_) async => _streamed(
        statusCode: 200,
        chunks: [bytes.sublist(0, 10), bytes.sublist(10)],
      ),
    );
    await expectLater(
      fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: bytes.length - 1,
      ),
      throwsA(
        isA<RemoteJsonFetchException>().having(
          (e) => e.failure,
          'failure',
          RemoteJsonFailureKind.responseTooLarge,
        ),
      ),
    );
  });

  test('text/plain and missing Content-Type still accept JSON', () async {
    for (final headers in [
      {'content-type': 'text/plain'},
      <String, String>{},
    ]) {
      final client = _StreamClient(
        (_) async => _streamed(
          statusCode: 200,
          headers: headers,
          chunks: [utf8.encode('{"v":2}')],
        ),
      );
      final map = await fetchRemoteJsonMap(
        client: client,
        url: 'https://example.test/a',
        kind: kind,
        timeout: const Duration(seconds: 5),
        maxBytes: maxBytes,
      );
      expect(map['v'], 2);
    }
  });

  test('maxBytes constants cover current assets with headroom', () {
    // Local gacha history ~99 KiB; weights/daily are far smaller.
    expect(kRemoteJsonMaxBytesGachaBannerHistory, greaterThan(99 * 1024));
    expect(kRemoteJsonMaxBytesArtifactScoreWeights, 256 * 1024);
    expect(kRemoteJsonMaxBytesDailyMaterialSchedule, 256 * 1024);
    expect(kRemoteJsonMaxBytesGachaCalendar, 1024 * 1024);
    expect(kRemoteJsonMaxBytesAkashaBuilds, 4 * 1024 * 1024);
    expect(kRemoteJsonMaxBytesLeyLineOverflow, 256 * 1024);
  });

  test('exception toString has no URL or body', () {
    const e = RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.httpStatus,
      statusCode: 500,
    );
    final s = e.toString();
    expect(s, isNot(contains('https://')));
    expect(s, isNot(contains('example.test')));
    expect(s, isNot(contains('{')));
    expect(s, contains('httpStatus'));
  });
}
