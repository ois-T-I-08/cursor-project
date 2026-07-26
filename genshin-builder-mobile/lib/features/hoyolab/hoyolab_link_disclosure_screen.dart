import 'package:flutter/material.dart';

import '../settings/legal_documents_section.dart';
import '../../application/legal/legal_url_launcher.dart';

/// Explicit pre-link disclosure. Must be accepted before WebView / HoYoLAB APIs start.
class HoyolabLinkDisclosureScreen extends StatelessWidget {
  const HoyolabLinkDisclosureScreen({
    required this.launcher,
    super.key,
  });

  final LegalUrlLauncher launcher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('HoYoLAB 連携について')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      '連携を始める前に、次の内容を確認してください。',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const _Bullet('HoYoLAB 連携は任意です。'),
                    const _Bullet('連携しなくても、手動入力や主要機能は利用できます。'),
                    const _Bullet(
                      'Cookie その他の認証情報は、端末の Secure Storage に保存します。',
                    ),
                    const _Bullet(
                      '認証情報は HoYoLAB / HoYoverse へ直接送信されます。',
                    ),
                    const _Bullet(
                      '認証情報は運営者サーバーへ送信・保存しません。',
                    ),
                    const _Bullet('連携は設定画面からいつでも解除できます。'),
                    const _Bullet(
                      '連携解除時に、端末内の Cookie と認証情報を削除します。',
                    ),
                    const SizedBox(height: 16),
                    Text('関連文書', style: theme.textTheme.titleSmall),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('プライバシーポリシー'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _open(context, privacyPolicyUrl),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('利用規約'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _open(context, termsOfUseUrl),
                    ),
                  ],
                ),
              ),
              FilledButton(
                key: const Key('hoyolab-disclosure-accept'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('内容を理解して連携する'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('キャンセル'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    final ok = await launcher(uri);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ページを開けませんでした。')),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('・'),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
