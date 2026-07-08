class HoyolabConstants {
  HoyolabConstants._();

  static const defaultAppVersion = '4.13.0';
  static const language = 'ja-jp';
  static const loginUrl =
      'https://m.hoyolab.com/#/circles/2/30/feed?page_type=feed';
  static const cookieUrl = 'https://m.hoyolab.com';

  static const verifyLTokenUrl =
      'https://passport-api-sg.hoyolab.com/account/ma-passport/token/verifyLToken';
  static const getUserGameRolesUrl =
      'https://api-account-os.hoyolab.com/binding/api/getUserGameRolesByLtoken';
  static const dailyNoteUrl =
      'https://bbs-api-os.hoyolab.com/game_record/app/genshin/api/dailyNote';
  static const getAllRegionsUrl =
      'https://api-account-os.hoyolab.com/account/binding/api/getAllRegions';

  /// Battle Chronicle ベース URL（dailyNote と同系統を優先）
  static const gameRecordBaseUrls = [
    'https://bbs-api-os.hoyolab.com/game_record/app/genshin/api',
    'https://sg-public-api.hoyolab.com/event/game_record/genshin/api',
  ];
  static const characterListPath = '/character/list';
  static const characterLegacyPath = '/character';
  static const characterDetailPath = '/character/detail';
  static const spiralAbyssPath = '/spiralAbyss';
  static const roleCombatPath = '/role_combat';

  /// Battle Chronicle 用 client_type
  static const recordClientType = '5';

  /// ゲーム記録データのキャッシュ TTL
  static const ownedCharactersCacheTtl = Duration(minutes: 15);
  static const characterDetailCacheTtl = Duration(minutes: 10);
  static const adventureStatusCacheTtl = Duration(minutes: 30);

  /// サイレント扱い（ユーザー向けに簡潔メッセージへ変換）
  static const knownRetcodes = {
    -100, // login expired
    10102, // realtime notes off
    -502001, // character not exist
    -502002, // character data private
  };
}
