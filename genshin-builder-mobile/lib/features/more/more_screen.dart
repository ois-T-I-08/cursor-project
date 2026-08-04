import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/deferred_loader.dart';
import '../home/widgets/home_events_card.dart';
import '../hoyolab/widgets/adventure_status_card.dart';
import '../shared/feature_hub.dart';

/// Secondary tools and app/account management without duplicating main tabs.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('その他')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const FeatureHubIntro(
            icon: Icons.apps_outlined,
            title: 'ツールと設定',
            description: 'ガチャ情報、データ連携、通知などの補助機能です。',
          ),
          const SizedBox(height: 12),
          FeatureHubSection(
            title: 'ゲーム情報',
            children: [
              FeatureHubDestination(
                icon: Icons.casino_outlined,
                title: 'ガチャ',
                description: '開催中・予定のピックアップを確認',
                onTap: () => context.push('/gacha'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('開催中の情報', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const HomeEventsCard(),
          const SizedBox(height: 12),
          Text('アカウント', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          DeferredLoader(builder: (_) => const AdventureStatusCard()),
          const SizedBox(height: 12),
          FeatureHubSection(
            title: '連携と管理',
            children: [
              FeatureHubDestination(
                icon: Icons.link_outlined,
                title: 'HoYoLAB連携',
                description: '樹脂、デイリー、派遣の取得設定',
                onTap: () => context.push('/settings/hoyolab'),
              ),
              FeatureHubDestination(
                icon: Icons.settings_outlined,
                title: '設定',
                description: '同期、通知、データ管理、利用規約',
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
