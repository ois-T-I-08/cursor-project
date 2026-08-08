import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/feature_hub.dart';

/// Goal-oriented entry point for planning and tracking character growth.
class GrowthHubScreen extends StatelessWidget {
  const GrowthHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('育成')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const FeatureHubIntro(
            icon: Icons.trending_up,
            title: '育成を計画する',
            description: '今日集める素材から長期目標まで、育成に必要な機能をまとめています。',
          ),
          const SizedBox(height: 12),
          FeatureHubSection(
            title: '今日と計画',
            children: [
              FeatureHubDestination(
                icon: Icons.calendar_today_outlined,
                title: '今日の曜日素材',
                description: '本日入手できる天賦・武器素材を確認',
                onTap: () => context.push('/daily'),
              ),
              FeatureHubDestination(
                icon: Icons.route_outlined,
                title: '育成ルート',
                description: '目標と樹脂から育成手順を組み立てる',
                onTap: () => context.push('/growth-route'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FeatureHubSection(
            title: '集めるもの',
            children: [
              FeatureHubDestination(
                icon: Icons.bookmark_outline,
                title: '素材ブックマーク',
                description: '不足している素材をまとめて確認',
                onTap: () => context.push('/bookmarks'),
              ),
              FeatureHubDestination(
                icon: Icons.diamond_outlined,
                title: '聖遺物',
                description: 'セット効果と装備キャラを確認',
                onTap: () => context.push('/artifacts'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FeatureHubSection(
            title: '振り返る',
            children: [
              FeatureHubDestination(
                icon: Icons.timeline_outlined,
                title: '成長履歴',
                description: 'キャラや武器の育成記録を見る',
                onTap: () => context.push('/growth-timeline'),
              ),
              FeatureHubDestination(
                icon: Icons.health_and_safety_outlined,
                title: 'アカウント健康診断',
                description: '育成状況をカテゴリ別に確認',
                onTap: () => context.push('/account-health'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
