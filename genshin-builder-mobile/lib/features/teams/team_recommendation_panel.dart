import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/team_recommendations/backend_team_recommendation_api.dart';
import '../../domain/models/master_models.dart';
import '../../domain/team_recommendation/team_recommendation.dart';
import '../../providers/app_providers.dart';
import '../../providers/team_recommendation_providers.dart';

class TeamRecommendationPanel extends ConsumerStatefulWidget {
  const TeamRecommendationPanel({
    required this.attackerId,
    this.onApplyRecommendation,
    super.key,
  });
  final String attackerId;

  /// Applies a full recommendation to empty slots only (secondary action).
  final ValueChanged<List<String>>? onApplyRecommendation;

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
  String? _autoStartedFor;

  TeamRecommendationOptions get _options => TeamRecommendationOptions(
    half: _half,
    ownedOnly: _ownedOnly,
    enemy: _enemy,
    preference: _preference,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoStartIfNeeded());
  }

  @override
  void didUpdateWidget(covariant TeamRecommendationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attackerId != widget.attackerId) {
      _autoStartedFor = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoStartIfNeeded());
    }
  }

  void _autoStartIfNeeded() {
    if (!mounted) return;
    if (_autoStartedFor == widget.attackerId) return;
    final async = ref.read(
      teamRecommendationControllerProvider(widget.attackerId),
    );
    if (async.isLoading) {
      _autoStartedFor = widget.attackerId;
      return;
    }
    final job = async.valueOrNull;
    if (job != null) {
      _autoStartedFor = widget.attackerId;
      return;
    }
    _autoStartedFor = widget.attackerId;
    ref
        .read(teamRecommendationControllerProvider(widget.attackerId).notifier)
        .start(_options);
  }

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
              label: Text(
                currentJob == null && !state.hasError ? 'おすすめ編成を計算' : '再計算',
              ),
            ),
            const SizedBox(height: 12),
            state.when(
              loading:
                  () => const _JobProgress(label: '正規化済み育成データから候補を準備しています'),
              error:
                  (error, _) => _Failure(
                    error: error,
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
              'おすすめは螺旋の使用実績と共通ルールに基づく参考情報です。\n実際の戦闘では操作、敵の行動、被弾、移動、回線状況などにより結果が異なります。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Usage statistics: AZA.GG',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  bool _isLowQualityOnly(TeamRecommendationResult result) {
    if (result.recommendations.isEmpty) return true;
    return result.recommendations.every((value) => !value.observedByAza);
  }

  Widget _jobContent(TeamSimulationJob? job, Map<String, String> names) {
    if (job == null) {
      return const Text('アタッカーを基準に、AZA.GG実績と元素反応ルールから候補を生成します。');
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
        if (result.warning != null || _isLowQualityOnly(result))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              result.warning == 'abyssUnavailable' || _isLowQualityOnly(result)
                  ? '螺旋の使用実績データを取得できなかったため、簡易ルール候補のみ表示しています。精度は低くなります。'
                  : 'おすすめ候補の品質が低下しています。再計算を試してください。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        for (final recommendation in result.recommendations)
          TeamRecommendationCard(
            recommendation: recommendation,
            names: names,
            generatedAt: result.generatedAt,
            onApply:
                widget.onApplyRecommendation == null
                    ? null
                    : () => widget.onApplyRecommendation!(
                      recommendation.members,
                    ),
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
  const _Failure({required this.onRetry, this.error});
  final VoidCallback onRetry;
  final Object? error;
  @override
  Widget build(BuildContext context) {
    final detail = _failureDetail(error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('おすすめ編成を取得できませんでした。既存の編成・螺旋統計機能は引き続き利用できます。'),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('再試行'),
        ),
      ],
    );
  }
}

String? _failureDetail(Object? error) {
  if (error is TeamRecommendationApiException) {
    return switch (error.code) {
      'notConfigured' =>
        'バックエンドURLが未設定です。起動時に GENSHIN_BUILDER_API_BASE_URL を指定してください。',
      'timeout' => '通信がタイムアウトしました。',
      'networkError' => 'ネットワークエラーです。接続を確認してください。',
      'invalidAttacker' => '選択中のアタッカーを推薦用データへ変換できませんでした。',
      'requestFailed' => 'サーバーがリクエストを拒否しました。再試行してください。',
      _ => null,
    };
  }
  return null;
}

class TeamRecommendationCard extends StatelessWidget {
  const TeamRecommendationCard({
    required this.recommendation,
    required this.names,
    required this.generatedAt,
    this.onApply,
    super.key,
  });
  final TeamRecommendation recommendation;
  final Map<String, String> names;
  final DateTime generatedAt;
  final VoidCallback? onApply;
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
              '評価: ${recommendation.observedByAza ? 'AZA.GG使用実績' : 'ルールベース'}',
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
            if (onApply != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('この編成を入れる'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
