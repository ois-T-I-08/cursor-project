/**
 * キャラクター関連の型定義
 *
 * キャラクター・武器・素材のマスターデータは外部API（genshin.jmp.blue）から
 * サーバー側で取得し、DBへ保存したものを画面に表示する。
 * ユーザーの育成状況（レベル・天賦など）はマスターデータとは別テーブルで管理する。
 */

/** 元素の種類 */
export type Element =
  | "pyro" // 炎
  | "hydro" // 水
  | "electro" // 雷
  | "cryo" // 氷
  | "anemo" // 風
  | "geo" // 岩
  | "dendro"; // 草

/** 武器の種類 */
export type WeaponType =
  | "sword" // 片手剣
  | "claymore" // 両手剣
  | "polearm" // 長柄武器
  | "bow" // 弓
  | "catalyst"; // 法器

/** レアリティ（星の数） */
export type Rarity = 4 | 5;

/** キャラクターの基本情報（DBに保存されたマスターデータ） */
export interface Character {
  /** API上の識別子（例: "hu-tao"） */
  id: string;
  /** 表示名 */
  name: string;
  element: Element;
  weaponType: WeaponType;
  rarity: Rarity;
  /** 出身地域 */
  region: string;
  /** アイコン画像URL（APIから取得） */
  iconUrl?: string;
  /** アイコン画像がない場合の代替表示用絵文字 */
  emoji?: string;
  /** 聖遺物スコア計算タイプ（atk / hp / def / em） */
  scoreType?: string;
}

/** 聖遺物の部位 */
export type ArtifactSlotKey =
  | "flower" // 花
  | "plume" // 羽
  | "sands" // 時計
  | "goblet" // 杯
  | "circlet"; // 冠

/** 聖遺物のサブステータス1つ分 */
export interface ArtifactSubstat {
  /** ステータス名（例: "会心率"） */
  stat: string;
  /** 数値（%系は 12.4 のように % を除いた値） */
  value: number;
}

/** 聖遺物1部位分の装備情報 */
export interface ArtifactPiece {
  /** 装備セットのマスターID（未装備は空文字） */
  setId: string;
  /** メインステータス名 */
  mainStat: string;
  /** 強化レベル (0-20) */
  level: number;
  /** サブステータス（最大4つ） */
  substats: ArtifactSubstat[];
}

/** 5部位分の聖遺物装備情報 */
export type ArtifactState = Record<ArtifactSlotKey, ArtifactPiece>;

/**
 * ユーザーの育成状況
 * （DBに保存するデータ。Ver.1ではランダム発行のユーザーIDに紐づける）
 */
export interface CharacterProgress {
  /** 対象キャラクターのID */
  characterId: string;
  /** 現在のレベル (1-90) */
  level: number;
  /** 突破段階 (0-6) */
  ascension: number;
  /** 命ノ星座（凸数 0-6） */
  constellation: number;
  /** 天賦レベル：通常攻撃・元素スキル・元素爆発 (各1-10) */
  talents: {
    normalAttack: number;
    elementalSkill: number;
    elementalBurst: number;
  };
  /** 装備中の武器のマスターID（未設定は空文字） */
  weaponId: string;
  /** 装備中の武器名（表示用） */
  weaponName: string;
  /** 武器レベル (1-90) */
  weaponLevel: number;
  /** 精錬ランク (1-5) */
  weaponRefinement: number;
  /** 聖遺物の装備状況 */
  artifacts: ArtifactState;
  /** 育成完了フラグ */
  isCompleted: boolean;
  /** 自由メモ */
  memo: string;
  /** 最終更新日時（ISO文字列） */
  updatedAt: string;
}

/** 空の聖遺物1部位分を作る */
export function createEmptyArtifactPiece(): ArtifactPiece {
  return { setId: "", mainStat: "", level: 0, substats: [] };
}

/** 空の聖遺物5部位分を作る */
export function createEmptyArtifactState(): ArtifactState {
  return {
    flower: { ...createEmptyArtifactPiece(), mainStat: "HP" },
    plume: { ...createEmptyArtifactPiece(), mainStat: "攻撃力" },
    sands: createEmptyArtifactPiece(),
    goblet: createEmptyArtifactPiece(),
    circlet: createEmptyArtifactPiece(),
  };
}

/** キャラクター基本情報と育成状況をまとめた表示用の型 */
export interface CharacterWithProgress {
  character: Character;
  progress: CharacterProgress;
}
