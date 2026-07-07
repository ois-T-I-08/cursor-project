/**
 * 外部APIから取得したデータをアプリ内部で扱うための正規化済みの型。
 *
 * どのAPIプロバイダーを使っても、取得層はこの形に変換してから返す。
 * これによりプロバイダーを変更してもDB同期処理や画面側の修正が不要になる。
 */

/** 正規化済みキャラクターデータ */
export interface MasterCharacter {
  id: string;
  name: string;
  element: string; // pyro / hydro / electro / cryo / anemo / geo / dendro
  weaponType: string; // sword / claymore / polearm / bow / catalyst
  rarity: number;
  region: string;
  iconUrl: string;
  /** 聖遺物スコア計算タイプ（atk / hp / def / em） */
  scoreType: string;
}

/** 正規化済み武器データ */
export interface MasterWeapon {
  id: string;
  name: string;
  weaponType: string;
  rarity: number;
  iconUrl: string;
}

/** 正規化済み素材データ */
export interface MasterMaterial {
  id: string;
  name: string;
  category: string; // talent-book / boss-material / local-specialties など
  rarity: number | null;
  iconUrl: string;
}

/**
 * ゲームデータ取得プロバイダーのインターフェース。
 * 新しいAPI（Project Amber等）へ移行する場合は、
 * このインターフェースを実装したクラス/オブジェクトを追加するだけでよい。
 */
export interface GameDataProvider {
  /** プロバイダー名（同期ログ用） */
  readonly name: string;
  fetchCharacters(): Promise<MasterCharacter[]>;
  fetchWeapons(): Promise<MasterWeapon[]>;
  fetchMaterials(): Promise<MasterMaterial[]>;
}
