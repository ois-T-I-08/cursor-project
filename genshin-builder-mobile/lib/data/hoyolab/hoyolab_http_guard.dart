import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum HoyolabHttpFailure {
  httpStatus,
  emptyBody,
  responseTooLarge,
  htmlResponse,
  invalidEncoding,
  invalidJson,
  invalidRoot,
  timeout,
  network,
  insecureUrl,
}

/// HoYoLAB HTTP/JSON guard failures (no URL, cookie, token, or body text).
class HoyolabHttpException implements Exception {
  const HoyolabHttpException(this.failure, {this.statusCode});

  final HoyolabHttpFailure failure;
  final int? statusCode;

  @override
  String toString() => 'HoyolabHttpException(${failure.name})';
}

class HoyolabHttpGuard {
  const HoyolabHttpGuard._();

  static const int defaultMaxBytes = 2 * 1024 * 1024;

  /// Rejects non-HTTPS and credentialed URLs before any request is sent.
  static void ensureSafeHoyolabUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      throw const HoyolabHttpException(HoyolabHttpFailure.insecureUrl);
    }
  }

  /// Reads a streamed response, aborting as soon as [maxBytes] is exceeded.
  static Future<http.Response> readBoundedResponse(
    http.StreamedResponse streamed, {
    int maxBytes = defaultMaxBytes,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      unawaited(streamed.stream.drain<void>().catchError((_) {}));
      throw HoyolabHttpException(
        HoyolabHttpFailure.httpStatus,
        statusCode: streamed.statusCode,
      );
    }

    final declared = streamed.contentLength;
    if (declared != null && declared > maxBytes) {
      unawaited(streamed.stream.drain<void>().catchError((_) {}));
      throw const HoyolabHttpException(HoyolabHttpFailure.responseTooLarge);
    }

    final builder = BytesBuilder(copy: false);
    StreamSubscription<List<int>>? sub;
    final done = Completer<void>();
    var tooLarge = false;

    try {
      sub = streamed.stream.listen(
        (chunk) {
          if (tooLarge) return;
          if (builder.length + chunk.length > maxBytes) {
            tooLarge = true;
            unawaited(sub?.cancel());
            if (!done.isCompleted) {
              done.completeError(
                const HoyolabHttpException(HoyolabHttpFailure.responseTooLarge),
              );
            }
            return;
          }
          builder.add(chunk);
        },
        onError: (Object _, StackTrace st) {
          if (!done.isCompleted) {
            done.completeError(
              const HoyolabHttpException(HoyolabHttpFailure.network),
              st,
            );
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future.timeout(timeout);
    } on TimeoutException {
      await sub?.cancel();
      throw const HoyolabHttpException(HoyolabHttpFailure.timeout);
    } on HoyolabHttpException {
      rethrow;
    } catch (_) {
      await sub?.cancel();
      throw const HoyolabHttpException(HoyolabHttpFailure.network);
    } finally {
      await sub?.cancel();
    }

    final bytes = builder.takeBytes();
    return http.Response.bytes(
      bytes,
      streamed.statusCode,
      headers: streamed.headers,
      request: streamed.request,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  static void ensureHttpSuccess(
    http.Response response, {
    int maxBytes = defaultMaxBytes,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HoyolabHttpException(
        HoyolabHttpFailure.httpStatus,
        statusCode: response.statusCode,
      );
    }

    final bodyBytes = response.bodyBytes;
    if (bodyBytes.isEmpty) {
      throw const HoyolabHttpException(HoyolabHttpFailure.emptyBody);
    }
    if (bodyBytes.length > maxBytes) {
      throw const HoyolabHttpException(HoyolabHttpFailure.responseTooLarge);
    }

    final trimmed = _leadingNonWhitespaceByte(bodyBytes);
    if (trimmed == 0x3C) {
      throw const HoyolabHttpException(HoyolabHttpFailure.htmlResponse);
    }

    try {
      utf8.decode(bodyBytes, allowMalformed: false);
    } catch (_) {
      throw const HoyolabHttpException(HoyolabHttpFailure.invalidEncoding);
    }
  }

  static Map<String, dynamic> decodeJsonObject(
    http.Response response, {
    int maxBytes = defaultMaxBytes,
  }) {
    ensureHttpSuccess(response, maxBytes: maxBytes);
    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: false),
      );
    } catch (_) {
      throw const HoyolabHttpException(HoyolabHttpFailure.invalidJson);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const HoyolabHttpException(HoyolabHttpFailure.invalidRoot);
    }
    return decoded;
  }

  static int? _leadingNonWhitespaceByte(List<int> bytes) {
    for (final byte in bytes) {
      if (byte != 0x20 &&
          byte != 0x09 &&
          byte != 0x0A &&
          byte != 0x0D &&
          byte != 0x0C) {
        return byte;
      }
    }
    return null;
  }
}
