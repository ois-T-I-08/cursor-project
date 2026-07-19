import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/user_facing_error.dart';
import '../../domain/abyss/abyss_statistics.dart';
import '../../providers/abyss_statistics_providers.dart';
import '../shared/game_icon_image.dart';
import '../shared/shell_menu_button.dart';

class AbyssStatisticsScreen extends ConsumerWidget {
  const AbyssStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statistics = ref.watch(abyssStatisticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('深境螺旋統計'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: () => ref.invalidate(abyssStatisticsProvider),
            icon: const Icon(Icons.refresh),
          ),
          const ShellMenuButton(),
        ],
      ),
      body: statistics.when(
        loading:
            () => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('統計データを読み込んでいます…'),
                ],
              ),
            ),
        error:
            (error, _) => _ErrorView(
              message: userFacingError(error),
              onRetry: () => ref.invalidate(abyssStatisticsProvider),
            ),
        data: (data) => _StatisticsView(data: data),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsView extends StatelessWidget {
  const _StatisticsView({required this.data});

  final AbyssStatistics data;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'キャラクター'), Tab(text: '編成')]),
          Expanded(
            child: TabBarView(
              children: [_CharacterTab(data: data), _TeamTab(data: data)],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsHeader extends StatelessWidget {
  const _StatisticsHeader({required this.data});

  final AbyssStatistics data;

  @override
  Widget build(BuildContext context) {
    final metadata = data.metadata;
    final version = data.version;
    final date = DateFormat('yyyy/MM/dd HH:mm');
    final day = DateFormat('yyyy/MM/dd');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metadata.isStale)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.history),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('前回取得した統計データを表示しています。最新情報ではない可能性があります。'),
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${metadata.source.displayName} 深境螺旋統計',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _MetadataLine(
                  label: '対象期間',
                  value:
                      '${day.format(version.periodStart.toLocal())} ～ ${day.format(version.periodEnd.toLocal())}',
                ),
                _MetadataLine(
                  label: 'スケジュールID',
                  value: '${version.scheduleId}',
                ),
                _MetadataLine(
                  label: 'API仕様',
                  value: '${version.sourceApiVersion}（ゲームバージョンではありません）',
                ),
                _MetadataLine(
                  label: '提供元更新',
                  value: date.format(metadata.sourceUpdatedAt.toLocal()),
                ),
                _MetadataLine(
                  label: '最終取得',
                  value: date.format(metadata.fetchedAt.toLocal()),
                ),
                _MetadataLine(
                  label: 'サンプル（origin）',
                  value:
                      '${metadata.sampleSize}（ref ${metadata.referenceSampleSize}）',
                ),
                _MetadataLine(
                  label: '収集進捗',
                  value: _percent(metadata.collectionProgress),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text('投稿データに基づく参考統計です。'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Text(
            'Statistics data provided by AZA.GG',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _CharacterTab extends StatelessWidget {
  const _CharacterTab({required this.data});

  final AbyssStatistics data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _StatisticsHeader(data: data),
        if (data.characters.isEmpty)
          const _EmptyMessage(message: '表示できるキャラクター統計がありません。')
        else
          for (final character in data.characters)
            _CharacterCard(character: character),
      ],
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character});

  final AbyssCharacterStatistic character;

  @override
  Widget build(BuildContext context) {
    final name = character.characterName ?? 'キャラクターID ${character.characterId}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: GameIconImage(
          iconUrl: character.iconUrl,
          size: 44,
          fallback: const Icon(Icons.person_outline),
        ),
        title: Text(name),
        subtitle: Text('今期の使用率 ${_percent(character.usageRate)}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RateLine(label: '所持者内使用率', value: character.usageAmongOwnersRate),
          _RateLine(label: '所持率', value: character.ownershipRate),
          if (character.upperHalfRate != null)
            _RateLine(label: '上半', value: character.upperHalfRate!),
          if (character.lowerHalfRate != null)
            _RateLine(label: '下半', value: character.lowerHalfRate!),
          if (character.constellationRates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('命ノ星座', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final item in character.constellationRates)
                  Text('${item.constellation}凸 ${_percent(item.rate)}'),
              ],
            ),
          ],
          if (character.weapons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('武器', style: Theme.of(context).textTheme.titleSmall),
            for (final item in character.weapons.take(5))
              _BuildLine(
                label: item.displayName ?? '武器ID ${item.id}',
                value: item.usageRate,
              ),
          ],
          if (character.artifacts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('聖遺物セット', style: Theme.of(context).textTheme.titleSmall),
            for (final item in character.artifacts.take(5))
              _BuildLine(
                label: item.setPieces
                    .map(
                      (piece) =>
                          'セットID ${piece.artifactSetId} ${piece.pieces}点',
                    )
                    .join(' + '),
                value: item.usageRate,
              ),
          ],
        ],
      ),
    );
  }
}

class _RateLine extends StatelessWidget {
  const _RateLine({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(_percent(value))],
      ),
    );
  }
}

class _BuildLine extends StatelessWidget {
  const _BuildLine({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Text(_percent(value)),
        ],
      ),
    );
  }
}

class _TeamTab extends StatelessWidget {
  const _TeamTab({required this.data});

  final AbyssStatistics data;

  @override
  Widget build(BuildContext context) {
    final upper = data.teams.where((team) => team.half == AbyssTeamHalf.upper);
    final lower = data.teams.where((team) => team.half == AbyssTeamHalf.lower);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _StatisticsHeader(data: data),
        if (data.teams.isEmpty)
          const _EmptyMessage(message: '表示できる編成統計がありません。')
        else ...[
          _TeamSection(title: '上半', teams: upper),
          const SizedBox(height: 12),
          _TeamSection(title: '下半', teams: lower),
        ],
      ],
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({required this.title, required this.teams});

  final String title;
  final Iterable<AbyssTeamStatistic> teams;

  @override
  Widget build(BuildContext context) {
    final items = teams.toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final team in items) _TeamCard(team: team),
      ],
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team});

  final AbyssTeamStatistic team;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final member in team.members)
                  Expanded(child: _TeamMemberView(member: member)),
              ],
            ),
            const Divider(height: 20),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 4,
              spacing: 12,
              children: [
                Text('使用率 ${_percent(team.usageRate)}'),
                Text('所持者内 ${_percent(team.usageAmongOwnersRate)}'),
                Text('所持率 ${_percent(team.ownershipRate)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamMemberView extends StatelessWidget {
  const _TeamMemberView({required this.member});

  final AbyssTeamMember member;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GameIconImage(
          iconUrl: member.iconUrl,
          size: 42,
          fallback: const Icon(Icons.person_outline),
        ),
        const SizedBox(height: 4),
        Text(
          member.characterName ?? member.characterId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.query_stats_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message),
        ],
      ),
    );
  }
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
