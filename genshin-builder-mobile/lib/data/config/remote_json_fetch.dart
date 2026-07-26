import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Artifact score weights remote body cap.
/// Local asset is ~0.8 KiB; full roster remote is expected well under this.
const int kRemoteJsonMaxBytesArtifactScoreWeights = 256 * 1024;

/// Daily material schedule remote body cap.
/// Local asset is ~7 KiB; headroom for series growth.
const int kRemoteJsonMaxBytesDailyMaterialSchedule = 256 * 1024;

/// Gacha banner history remote body cap.
/// Local asset is ~99 KiB (~210 banners); allow growth toward ~1 MiB.
const int kRemoteJsonMaxBytesGachaBannerHistory = 1024 * 1024;

/// Live calendar response cap. The payload is expected to stay well below 1 MiB.
const int kRemoteJsonMaxBytesGachaCalendar = 1024 * 1024;

/// Akasha builds page cap. A page contains at most 50 builds by default.
const int kRemoteJsonMaxBytesAkashaBuilds = 4 * 1024 * 1024;

/// Ley Line Overflow catalog cap. The bundled catalog is under 1 KiB.
const int kRemoteJsonMaxBytesLeyLineOverflow = 256 * 1024;

enum RemoteJsonFailureKind {
  invalidUrl,
  timeout,
  networkError,
  httpStatus,
  responseTooLarge,
  invalidEncoding,
  invalidJson,
  invalidRootType,
  unexpected,
}

/// Safe remote JSON fetch failure (no URL / body / headers / secrets).
class RemoteJsonFetchException implements Exception {
  const RemoteJsonFetchException({
    required this.kind,
    required this.failure,
    this.statusCode,
    this.timeout,
    this.maxBytes,
    this.receivedBytes,
    this.contentTypePresent = false,
  });

  final String kind;
  final RemoteJsonFailureKind failure;
  final int? statusCode;
  final Duration? timeout;
  final int? maxBytes;
  final int? receivedBytes;
  final bool contentTypePresent;

  String get reasonCode => failure.name;

  @override
  String toString() =>
      'RemoteJsonFetchException(kind=$kind, failure=${failure.name}'
      '${statusCode != null ? ', status=$statusCode' : ''}'
      '${receivedBytes != null ? ', receivedBytes=$receivedBytes' : ''}'
      ')';
}

/// Streaming GET → Map. Does not create or close [client].
Future<Map<String, dynamic>> fetchRemoteJsonMap({
  required http.Client client,
  required String url,
  required String kind,
  required Duration timeout,
  required int maxBytes,
  Map<String, String>? headers,
}) async {
  late final Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.invalidUrl,
    );
  }
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.invalidUrl,
    );
  }

  http.StreamedResponse streamed;
  try {
    final request =
        http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll(headers ?? const {});
    streamed = await client.send(request).timeout(timeout);
  } on TimeoutException {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.timeout,
      timeout: timeout,
      maxBytes: maxBytes,
    );
  } on SocketException {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.networkError,
      maxBytes: maxBytes,
    );
  } on http.ClientException {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.networkError,
      maxBytes: maxBytes,
    );
  } on HttpException {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.networkError,
      maxBytes: maxBytes,
    );
  } on RemoteJsonFetchException {
    rethrow;
  } catch (_) {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.unexpected,
      maxBytes: maxBytes,
    );
  }

  final contentTypePresent =
      streamed.headers.containsKey('content-type') ||
      streamed.headers.containsKey('Content-Type');

  if (streamed.statusCode != 200) {
    // Drain without retaining body for logs.
    unawaited(streamed.stream.drain<void>().catchError((_) {}));
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.httpStatus,
      statusCode: streamed.statusCode,
      maxBytes: maxBytes,
      contentTypePresent: contentTypePresent,
    );
  }

  final declared = streamed.contentLength;
  if (declared != null && declared > maxBytes) {
    unawaited(streamed.stream.drain<void>().catchError((_) {}));
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.responseTooLarge,
      statusCode: streamed.statusCode,
      maxBytes: maxBytes,
      receivedBytes: declared,
      contentTypePresent: contentTypePresent,
    );
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
          final total = builder.length + chunk.length;
          unawaited(sub?.cancel());
          if (!done.isCompleted) {
            done.completeError(
              RemoteJsonFetchException(
                kind: kind,
                failure: RemoteJsonFailureKind.responseTooLarge,
                statusCode: streamed.statusCode,
                maxBytes: maxBytes,
                receivedBytes: total,
                contentTypePresent: contentTypePresent,
              ),
            );
          }
          return;
        }
        builder.add(chunk);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) {
          done.completeError(
            RemoteJsonFetchException(
              kind: kind,
              failure: RemoteJsonFailureKind.networkError,
              statusCode: streamed.statusCode,
              maxBytes: maxBytes,
              receivedBytes: builder.length,
              contentTypePresent: contentTypePresent,
            ),
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
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.timeout,
      timeout: timeout,
      maxBytes: maxBytes,
      receivedBytes: builder.length,
      contentTypePresent: contentTypePresent,
    );
  } on RemoteJsonFetchException {
    await sub?.cancel();
    rethrow;
  } catch (_) {
    await sub?.cancel();
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.unexpected,
      maxBytes: maxBytes,
      receivedBytes: builder.length,
      contentTypePresent: contentTypePresent,
    );
  } finally {
    await sub?.cancel();
  }

  final bytes = builder.takeBytes();
  if (bytes.isEmpty) {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.invalidJson,
      statusCode: 200,
      maxBytes: maxBytes,
      receivedBytes: 0,
      contentTypePresent: contentTypePresent,
    );
  }

  if (_looksLikeHtml(bytes)) {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.invalidJson,
      statusCode: 200,
      maxBytes: maxBytes,
      receivedBytes: bytes.length,
      contentTypePresent: contentTypePresent,
    );
  }

  late final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.invalidEncoding,
      statusCode: 200,
      maxBytes: maxBytes,
      receivedBytes: bytes.length,
      contentTypePresent: contentTypePresent,
    );
  }

  late final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.invalidJson,
      statusCode: 200,
      maxBytes: maxBytes,
      receivedBytes: bytes.length,
      contentTypePresent: contentTypePresent,
    );
  }

  if (decoded is! Map) {
    throw RemoteJsonFetchException(
      kind: kind,
      failure: RemoteJsonFailureKind.invalidRootType,
      statusCode: 200,
      maxBytes: maxBytes,
      receivedBytes: bytes.length,
      contentTypePresent: contentTypePresent,
    );
  }

  return Map<String, dynamic>.from(decoded);
}

bool _looksLikeHtml(Uint8List bytes) {
  var i = 0;
  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    i = 3;
  }
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) {
      i++;
      continue;
    }
    break;
  }
  if (i >= bytes.length) return false;
  if (bytes[i] != 0x3C) return false; // '<'

  final end = (i + 16).clamp(i, bytes.length);
  final prefix = String.fromCharCodes(bytes.sublist(i, end)).toLowerCase();
  // Any markup-looking payload after whitespace; JSON objects start with '{'.
  return prefix.startsWith('<!doctype') ||
      prefix.startsWith('<html') ||
      prefix.startsWith('<');
}
