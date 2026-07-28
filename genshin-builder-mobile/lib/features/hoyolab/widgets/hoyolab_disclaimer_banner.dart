import 'package:flutter/material.dart';

/// HoYoLAB 連携に関する非公式・Cookie 注意表示
class HoyolabDisclaimerBanner extends StatelessWidget {
  const HoyolabDisclaimerBanner({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text =
        compact
            ? '非公式ツール。Cookie は端末内のみ暗号化保存。'
            : '本機能は非公式ファンツールです。miHoYo / HoYoverse とは無関係です。\n'
                'HoYoLAB のログイン Cookie を端末内に暗号化保存し、樹脂等の表示にのみ使用します。'
                'Cookie をログや外部に送信しません。';

    return Card(
      color: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              size: compact ? 18 : 22,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
