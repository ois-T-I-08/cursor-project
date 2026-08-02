import 'package:flutter/foundation.dart';

import 'remote_json_fetch.dart';

/// Failure kinds for local / schema config loads (safe for logs, not for UI).
enum ConfigLoadFailureKind {
  assetMissing,
  invalidJson,
  invalidRootType,
  schemaInvalid,
  unexpected,
}

/// Safe config load failure (no URL / body / asset path / secrets in UI).
class ConfigLoadException implements Exception {
  const ConfigLoadException({
    required this.kind,
    required this.failure,
    this.field,
  });

  final String kind;
  final ConfigLoadFailureKind failure;
  final String? field;

  String get reasonCode => failure.name;

  @override
  String toString() =>
      'ConfigLoadException(kind=$kind, failure=${failure.name}'
      '${field != null ? ', field=$field' : ''})';
}

typedef ConfigLoadLogSink = void Function(String line);

/// Testable sink; default prints in debug only.
ConfigLoadLogSink? configLoadLogSink;

/// One-line safe metadata log. No URL / body / JSON / secrets.
void logConfigLoad({
  required String kind,
  required String source,
  required String result,
  required String reason,
  String? field,
  int? status,
  int? maxBytes,
  int? receivedBytes,
}) {
  final buf = StringBuffer(
    'config_load kind=$kind source=$source result=$result reason=$reason',
  );
  if (field != null && field.isNotEmpty) {
    buf.write(' field=$field');
  }
  if (status != null) buf.write(' status=$status');
  if (maxBytes != null) buf.write(' maxBytes=$maxBytes');
  if (receivedBytes != null) buf.write(' receivedBytes=$receivedBytes');
  final line = buf.toString();
  final sink = configLoadLogSink;
  if (sink != null) {
    sink(line);
    return;
  }
  if (kDebugMode) {
    debugPrint(line);
  }
}

/// Map FormatException message to a short safe field token when possible.
String? safeFieldFromFormatException(FormatException e) {
  final m = e.message;
  final match = RegExp(r'\b([a-zA-Z][a-zA-Z0-9_.]*)\b').firstMatch(m);
  final token = match?.group(1);
  if (token == null) return null;
  const allowed = {
    'profiles',
    'characterId',
    'weights',
    'version',
    'talentSeries',
    'weaponSeries',
    'artifactSeries',
    'weeklyBossSeries',
    'materialIds',
    'days',
    'id',
    'banners',
    'type',
    'name',
    'start',
    'end',
  };
  if (allowed.contains(token)) return token;
  return null;
}

ConfigLoadException configLoadFromFormatException({
  required String kind,
  required FormatException error,
}) {
  return ConfigLoadException(
    kind: kind,
    failure: ConfigLoadFailureKind.schemaInvalid,
    field: safeFieldFromFormatException(error),
  );
}

String configFailureReason(Object error) {
  if (error is RemoteJsonFetchException) return error.reasonCode;
  if (error is ConfigLoadException) return error.reasonCode;
  if (error is FormatException) return ConfigLoadFailureKind.schemaInvalid.name;
  return 'unexpected';
}

void logRemoteFallback({required String kind, required Object error}) {
  logConfigLoad(
    kind: kind,
    source: 'remote',
    result: 'fallback',
    reason: configFailureReason(error),
    field: error is ConfigLoadException ? error.field : null,
    status: error is RemoteJsonFetchException ? error.statusCode : null,
    maxBytes: error is RemoteJsonFetchException ? error.maxBytes : null,
    receivedBytes:
        error is RemoteJsonFetchException ? error.receivedBytes : null,
  );
}

void logLocalConfigFailed({required String kind, required Object error}) {
  logConfigLoad(
    kind: kind,
    source: 'local',
    result: 'failed',
    reason: configFailureReason(error),
    field: error is ConfigLoadException ? error.field : null,
  );
}
