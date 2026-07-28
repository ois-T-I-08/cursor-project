import 'package:http/http.dart' as http;

import '../config/config_load_log.dart';
import '../config/config_validators.dart';
import '../config/remote_json_fetch.dart';
import 'artifact_score_weight.dart';
import 'artifact_score_weight_source.dart';

const _configKind = 'artifact_score_weights';

class RemoteArtifactScoreWeightSource
    implements RefreshableArtifactScoreWeightSource {
  RemoteArtifactScoreWeightSource({
    required this.url,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String url;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<List<ArtifactScoreWeightProfile>> loadProfiles() => refreshProfiles();

  @override
  Future<List<ArtifactScoreWeightProfile>> refreshProfiles() async {
    if (url.isEmpty) return const [];
    final decoded = await fetchRemoteJsonMap(
      client: _client,
      url: url,
      kind: _configKind,
      timeout: timeout,
      maxBytes: kRemoteJsonMaxBytesArtifactScoreWeights,
    );
    try {
      validateArtifactScoreWeightsJson(decoded);
    } on FormatException catch (e) {
      throw configLoadFromFormatException(kind: _configKind, error: e);
    }
    try {
      return (decoded['profiles'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (e) => ArtifactScoreWeightProfile.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.unexpected,
      );
    }
  }
}
