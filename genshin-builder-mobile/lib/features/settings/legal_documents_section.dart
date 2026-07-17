import 'package:flutter/material.dart';

import '../../application/legal/legal_url_launcher.dart';

const privacyPolicyUrl = 'https://ois-t-i-08.github.io/.github.io/privacy.html';
const termsOfUseUrl = 'https://ois-t-i-08.github.io/.github.io/terms.html';

class LegalDocumentsSection extends StatefulWidget {
  const LegalDocumentsSection({super.key, required this.launcher});

  final LegalUrlLauncher launcher;

  @override
  State<LegalDocumentsSection> createState() => _LegalDocumentsSectionState();
}

class _LegalDocumentsSectionState extends State<LegalDocumentsSection> {
  bool _opening = false;

  Future<void> _open(String url) async {
    if (_opening) return;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _showLaunchError();
      return;
    }

    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await widget.launcher(uri);
    } catch (_) {
      opened = false;
    }

    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) _showLaunchError();
  }

  void _showLaunchError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('ページを開けませんでした。通信環境またはブラウザ設定を確認してください。')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text('法的情報', style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('privacy-policy-link'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('プライバシーポリシー'),
            subtitle: const Text('外部ブラウザで開きます'),
            trailing: const Icon(Icons.open_in_new),
            enabled: !_opening,
            onTap: _opening ? null : () => _open(privacyPolicyUrl),
          ),
          ListTile(
            key: const Key('terms-of-use-link'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('利用規約'),
            subtitle: const Text('外部ブラウザで開きます'),
            trailing: const Icon(Icons.open_in_new),
            enabled: !_opening,
            onTap: _opening ? null : () => _open(termsOfUseUrl),
          ),
        ],
      ),
    );
  }
}
