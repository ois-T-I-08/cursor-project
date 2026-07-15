import 'dart:convert';

import 'package:http/http.dart' as http;

enum HoyolabHttpFailure {
  httpStatus,
  emptyBody,
  responseTooLarge,
  htmlResponse,
  invalidEncoding,
  invalidJson,
  invalidRoot,
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
