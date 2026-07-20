import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/team_recommendations/backend_team_recommendation_api.dart';
import '../../domain/models/master_models.dart';
import '../../domain/team_recommendation/team_recommendation.dart';
import '../../providers/app_providers.dart';
import '../../providers/team_recommendation_providers.dart';

class TeamRecommendationPanel extends ConsumerStatefulWidget {
  const TeamRecommendationPanel({required this.attackerId, super.key});
  final String attackerId;

  @override
  ConsumerState<TeamRecommendationPanel> createState() =>
      _TeamRecommendationPanelState();
}

class _TeamRecommendationPanelState
    extends ConsumerState<TeamRecommendationPanel> {
  bool _ownedOnly = true;
  String _half = 'upper';
  String _enemy = 'single';
  String _preference = 'damage';

  TeamRecommendationOptions get _options => TeamRecommendationOptions(
    half: _half,
    ownedOnly: _ownedOnly,
    enemy: _enemy,
    preference: _preference,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(
      teamRecommendationControllerProvider(widget.attackerId),
    );
    final currentJob = state.valueOrNull;
    final isBusy =
        state.isLoading ||
        currentJob?.status == TeamSimulationJobStatus.queued ||
        currentJob?.status == TeamSimulationJobStatus.running;
    final characters =
        ref.watch(charactersProvider).valueOrNull ?? const <MasterCharacter>[];
    final names = {for (final value in characters) value.id: value.name};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('おすすめ編成', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('所持キャラのみ'),
              subtitle: const Text('オフにすると未所持キャラを含む候補も表示します'),
              value: _ownedOnly,
              onChanged: (value) => setState(() => _ownedOnly = value),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _selector('螺旋', _half, const {
                  'upper': '上半',
                  'lower': '下半',
                }, (value) => setState(() => _half = value)),
                _selector('敵', _enemy, const {
                  'single': '単体敵',
                  'multiple': '複数敵',
                }, (value) => setState(() => _enemy = value)),
                _selector('重視', _preference, const {
                  'damage': '高火力',
                  'stability': '安定性',
                  'fourStar': '星4中心',
                  'built': '育成済み',
                }, (value) => setState(() => _preference = value)),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  isBusy
                      ? null
                      : () => ref
                          .read(
                            teamRecommendationControllerProvider(
                              widget.attackerId,
                            ).notifier,
                          )
                          .start(_options),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('おすすめ編成を計算'),
            ),
            const SizedBox(height: 12),
            state.when(
              loading:
                  () => const _JobProgress(label: '正規化済み育成データから候補を準備しています'),
              error:
                  (error, _) => _Failure(
                    message: _errorMessage(error),
                    onRetry:
                        () =>
                            ref
                                .read(
                                  teamRecommendationControllerProvider(
                                    widget.attackerId,
                                  ).notifier,
                                )
                                .retry(),
                  ),
              data: (job) => _jobContent(job, names),
            ),
            const Divider(height: 24),
            Text(
              'シミュレーション結果は理論値です。\n実際の戦闘では操作、敵の行動、被弾、移動、回線状況などにより結果が異なります。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Simulation: gcsim (MIT License) / Usage statistics: AZA.GG',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobContent(TeamSimulationJob? job, Map<String, String> names) {
    if (job == null) {
      return const Text('アタッカーを基準に、AZA.GG実績・元素反応ルール・gcsimを組み合わせて候補を生成します。');
    }
    if (job.status == TeamSimulationJobStatus.queued) {
      return const _JobProgress(label: '待機中です');
    }
    if (job.status == TeamSimulationJobStatus.running) {
      return const _JobProgress(label: '編成を評価しています');
    }
    if (job.status == TeamSimulationJobStatus.failed ||
        job.status == TeamSimulationJobStatus.expired) {
      return _Failure(
        message: 'おすすめ編成の計算に失敗しました。時間をおいて再試行してください。',
        onRetry:
            () =>
                ref
                    .read(
                      teamRecommendationControllerProvider(
                        widget.attackerId,
                      ).notifier,
                    )
                    .retry(),
      );
    }
    final result = job.result;
    if (result == null) return const Text('結果を読み込めませんでした。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.warning != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              result.warning == 'staleSimulation'
                  ? '前回の正常なシミュレーション結果を表示しています。'
                  : 'gcsimでシミュレーションできませんでした（未対応キャラ／武器、または育成データ不足）。AZA.GG実績とルールに基づく候補を表示しています。',
            ),
          ),
        for (final recommendation in result.recommendations)
          TeamRecommendationCard(
            recommendation: recommendation,
            names: names,
            generatedAt: result.generatedAt,
          ),
      ],
    );
  }

  Widget _selector(
    String label,
    String value,
    Map<String, String> values,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButton<String>(
      value: value,
      items:
          values.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text('$label: ${entry.value}'),
                ),
              )
              .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class _JobProgress extends StatelessWidget {
  const _JobProgress({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry, this.message});
  final VoidCallback onRetry;
  final String? message;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        message ??
            'おすすめ編成を取得できませんでした。既存の編成・螺旋統計機能は引き続き利用できます。',
      ),
      TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('再試行'),
      ),
    ],
  );
}

String _errorMessage(Object error) {
  if (error is TeamRecommendationApiException) {
    return switch (error.code) {
      'notConfigured' => 'おすすめ編成の接続先が設定されていません。',
      'attackerUnavailable' =>
        'このキャラではおすすめ編成を計算できません（旅人の複合IDなど未対応の場合があります）。',
      'timeout' => 'おすすめ編成の取得がタイムアウトしました。再試行してください。',
      'networkError' => '通信に失敗しました。接続を確認して再試行してください。',
      'invalidRequest' || 'requestFailed' =>
        '送信データの形式を確認できませんでした。所持キャラ同期後に再試行してください。',
      _ => 'おすすめ編成を取得できませんでした。既存の編成・螺旋統計機能は引き続き利用できます。',
    };
  }
  return 'おすすめ編成を取得できませんでした。既存の編成・螺旋統計機能は引き続き利用できます。';
}

class TeamRecommendationCard extends StatelessWidget {
  const TeamRecommendationCard({
    required this.recommendation,
    required this.names,
    required this.generatedAt,
    super.key,
  });
  final TeamRecommendation recommendation;
  final Map<String, String> names;
  final DateTime generatedAt;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in recommendation.members)
                  Chip(label: Text(names[id] ?? id)),
              ],
            ),
            Text(
              'おすすめスコア ${(recommendation.score * 100).toStringAsFixed(0)} / 100',
            ),
            Text(
              recommendation.estimatedDps == null
                  ? '推定DPS: 未シミュレーション'
                  : '推定DPS: ${recommendation.estimatedDps!.toStringAsFixed(0)}',
            ),
            Text(
              '評価: ${recommendation.simulationStatus == 'simulated'
                  ? 'シミュレーション済み'
                  : recommendation.observedByAza
                  ? 'AZA.GG使用実績'
                  : 'ルールベース'}${recommendation.isCached ? '（キャッシュ）' : ''}${recommendation.isStale ? '（前回値）' : ''}',
            ),
            Text(
              '入力品質: ${recommendation.inputQuality.name} / ローテーション信頼度: ${recommendation.rotationConfidence}',
            ),
            Text('更新: ${generatedAt.toLocal()}'),
            for (final reason in recommendation.reasons)
              Text('・$reason', style: theme.textTheme.bodySmall),
            if (recommendation.alternatives.isNotEmpty)
              Text(
                '代替キャラクター: ${recommendation.alternatives.values.expand((value) => value).map((id) => names[id] ?? id).join('、')}',
              ),
          ],
        ),
      ),
    );
  }
}
