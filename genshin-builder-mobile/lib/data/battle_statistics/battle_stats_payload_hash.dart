import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/battle_statistics/battle_statistics.dart';
import '../../domain/repositories/battle_statistics_repository.dart';

class Sha256BattleStatsIntegrityVerifier
    implements BattleStatsIntegrityVerifier {
  const Sha256BattleStatsIntegrityVerifier();

  @override
  bool matches(BattleStatsBundle bundle) {
    final digest = sha256.convert(
      utf8.encode(_stableStringify(_hashable(bundle))),
    );
    return bundle.payloadHash == 'sha256:$digest';
  }

  Object _hashable(BattleStatsBundle bundle) {
    final teams =
        bundle.teams.map((team) {
            final members = [...team.members]..sort();
            return <String, Object>{
              'teamKey': team.teamKey,
              'members': members,
              'usageRate': team.usageRate,
              if (team.usageCount != null) 'usageCount': team.usageCount!,
              if (team.rank != null) 'rank': team.rank!,
              if (team.side != null) 'side': team.side!,
              if (team.stageKey != null) 'stageKey': team.stageKey!,
              if (team.sampleSize != null) 'sampleSize': team.sampleSize!,
              'isResolved': true,
              'sourceMetadata': <String, Object>{},
            };
          }).toList()
          ..sort((left, right) {
            final leftKey =
                '${left['teamKey']}|${left['side'] ?? ''}|${left['stageKey'] ?? ''}';
            final rightKey =
                '${right['teamKey']}|${right['side'] ?? ''}|${right['stageKey'] ?? ''}';
            return leftKey.compareTo(rightKey);
          });
    final characters =
        bundle.characters.map((character) {
            return <String, Object>{
              'characterId': character.characterId,
              'usageRate': character.usageRate,
              if (character.usageCount != null)
                'usageCount': character.usageCount!,
              if (character.rank != null) 'rank': character.rank!,
              if (character.side != null) 'side': character.side!,
              if (character.ownershipRate != null)
                'ownershipRate': character.ownershipRate!,
              if (character.usageAmongOwnersRate != null)
                'usageAmongOwnersRate': character.usageAmongOwnersRate!,
              if (character.sampleSize != null)
                'sampleSize': character.sampleSize!,
              'isResolved': true,
            };
          }).toList()
          ..sort((left, right) {
            final leftKey = '${left['characterId']}|${left['side'] ?? ''}';
            final rightKey = '${right['characterId']}|${right['side'] ?? ''}';
            return leftKey.compareTo(rightKey);
          });
    return <String, Object>{
      'source': 'YShelper',
      'contentType': bundle.contentType.name,
      'schemaVersion': bundle.schemaVersion,
      'sourceVersion': bundle.sourceVersion,
      'seasonId': bundle.seasonId,
      'sourceUpdatedAt': bundle.sourceUpdatedAt.toUtc().toIso8601String(),
      if (bundle.sampleSize != null) 'sampleSize': bundle.sampleSize!,
      'metadata': <String, Object>{},
      'teams': teams,
      'characters': characters,
    };
  }
}

String _stableStringify(Object? value) {
  if (value == null) return 'null';
  if (value is num) {
    if (!value.isFinite) throw const FormatException('non-finite number');
    final rounded = double.parse(value.toDouble().toStringAsFixed(8));
    return rounded == rounded.roundToDouble()
        ? '${rounded.toInt()}'
        : '$rounded';
  }
  if (value is String || value is bool) return jsonEncode(value);
  if (value is List) {
    return '[${value.map(_stableStringify).join(',')}]';
  }
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((key) {
      return '${jsonEncode(key)}:${_stableStringify(value[key])}';
    }).join(',')}}';
  }
  throw const FormatException('unsupported canonical JSON value');
}
