import 'package:flutter/material.dart';

import '../../../domain/models/master_models.dart';
import '../../../domain/level_config.dart';
import '../../shared/game_icon_image.dart';

/// キャラ詳細のアコーディオン要約: 装備武器とレベル
class CharacterWeaponSummary extends StatelessWidget {
  const CharacterWeaponSummary({
    super.key,
    required this.weapons,
    required this.weaponId,
    required this.weaponName,
    required this.weaponLevel,
    required this.targetWeaponLevel,
  });

  final List<MasterWeapon> weapons;
  final String weaponId;
  final String weaponName;
  final int weaponLevel;
  final int targetWeaponLevel;

  @override
  Widget build(BuildContext context) {
    if (weaponId.isEmpty && weaponName.isEmpty) {
      return const Text('武器未選択');
    }
    final weapon = weapons.where((w) => w.id == weaponId).firstOrNull;
    final name = weaponName.isEmpty ? '武器' : weaponName;
    final levelText =
        weaponLevel >= levelMax
            ? '最大強化済み Lv.$weaponLevel'
            : 'Lv.$weaponLevel → 目標 Lv.$targetWeaponLevel';

    return Row(
      children: [
        GameIconImage(iconUrl: weapon?.iconUrl, size: 32),
        const SizedBox(width: 8),
        Expanded(child: Text('$name · $levelText')),
      ],
    );
  }
}
