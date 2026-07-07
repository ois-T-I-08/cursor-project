import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  fetchArtifactSets,
  fetchAvatarDetail,
  fetchWeaponDetail,
} from "@/lib/api/amber-details";
import { getScoreType } from "@/lib/artifact-score";
import { getCharacter } from "@/lib/repository/characters";
import { getProgress } from "@/lib/repository/progress";
import { getWeaponsByType } from "@/lib/repository/weapons";
import { getUserId } from "@/lib/user";
import DetailEditor from "@/components/character/detail/DetailEditor";

interface Props {
  params: Promise<{ id: string }>;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params;
  const character = await getCharacter(id);
  return { title: character?.name ?? "キャラクター詳細" };
}

/**
 * キャラクター詳細画面（Server Component）
 *
 * ここで必要なデータをすべて取得し、編集操作は Client Component の
 * DetailEditor に任せる。スキル・凸・武器性能・聖遺物セットは
 * 外部API（キャッシュ付き）から取得し、取得に失敗しても
 * 基本情報と入力フォームだけで動作を継続する。
 */
export default async function CharacterDetailPage({ params }: Props) {
  const { id } = await params;
  const character = await getCharacter(id);

  if (!character) {
    notFound();
  }

  const userId = await getUserId();

  // 育成状況・武器一覧・スキル/凸情報・聖遺物セットを並列取得
  const [progress, weapons, avatarDetail, artifactSets] = await Promise.all([
    userId ? getProgress(userId, character.id) : Promise.resolve(null),
    getWeaponsByType(character.weaponType),
    fetchAvatarDetail(character.id),
    fetchArtifactSets(),
  ]);

  // 装備中の武器があれば、その性能詳細も取得しておく
  const initialWeaponDetail = progress?.weaponId
    ? await fetchWeaponDetail(progress.weaponId)
    : null;

  return (
    <div className="space-y-4">
      <Link href="/characters" className="text-sm text-accent hover:underline">
        ← キャラクター一覧へ戻る
      </Link>

      <DetailEditor
        character={character}
        initialProgress={progress}
        weapons={weapons}
        avatarDetail={avatarDetail}
        artifactSets={artifactSets}
        initialWeaponDetail={initialWeaponDetail}
        scoreType={getScoreType(character)}
      />
    </div>
  );
}
